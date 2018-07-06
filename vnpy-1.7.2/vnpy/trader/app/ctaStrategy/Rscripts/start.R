## =============================================================================
## start.R
## 在开盘的时候跑脚本
## 处理不同策略的订单
## =============================================================================

# rm(list = ls())

## =============================================================================
# args <- commandArgs(trailingOnly = TRUE)
# ROOT_PATH <- args[1]
# accountDB <- args[2]
ROOT_PATH = "/home/william/Documents/myCTP/vnpy-1.7.2"
accountDB <- 'SimNow_YY'
## =============================================================================
setwd(ROOT_PATH)
suppressWarnings(
    suppressMessages(
        source("./vnpy/trader/app/ctaStrategy/Rscripts/myInit.R")
))

ChinaFuturesCalendar <- fread("./vnpy/trader/ChinaFuturesCalendar.csv")

## -----------------------------------------------------------------------------
## 计算交易日历
if (as.numeric(format(Sys.time(),'%H')) < 17) {
    currTradingDay <- ChinaFuturesCalendar[days <= format(Sys.Date(),'%Y%m%d')][.N]
} else {
    currTradingDay <- ChinaFuturesCalendar[nights <= format(Sys.Date(),'%Y%m%d')][.N]
}
lastTradingday <- ChinaFuturesCalendar[days < currTradingDay[.N, days]][.N]
## -----------------------------------------------------------------------------

## =============================================================================
## 从 MySQL 数据库提取数据
## -----------------------------------------------------------------------------
mysql <- mysqlFetch(accountDB)
dbSendQuery(mysql, "set names utf8")
dbSendQuery(mysql, "truncate table tradingOrders;")
dbSendQuery(mysql, paste("delete from UpperLowerInfo where TradingDay !=",
                        currTradingDay[1, gsub('-','',days)]))
## =============================================================================

## -----------------------------------------------------------------------------
## HO 策略的持仓信息表
pos <- mysqlQuery(
    db = accountDB,
    query = "select * from positionInfo where strategyID = 'HOStrategy'")

if (nrow(pos) != 0) {
    ## 计算持仓时间
    ## 并选择持仓周期超过 5 天的作为平仓信号
    posHO <- pos[, .SD] %>% 
        .[, TradingDay := ymd(TradingDay)] %>%
        .[, holdingDays := lapply(1:.N, function(i){
            tmp <- ChinaFuturesCalendar[days %between% 
                    c(.SD[i, format(TradingDay,'%Y%m%d')],
                      currTradingDay[1,days])]
            return(nrow(tmp) - 1)
        })] %>% .[holdingDays >= 5]
    posHOtoday <- pos[gsub('-','',TradingDay) == currTradingDay[1,days]]
} else {
    posHO <- data.table()
    posHOtoday <- data.table()
}

print(posHO)
print(posHOtoday)
## -----------------------------------------------------------------------------

## -----------------------------------------------------------------------------
## OI 策略的持仓信息
posOI <- mysqlQuery(
    db = accountDB,
    query = paste(
        "select * from positionInfo where strategyID = 'OIStrategy'
        and TradingDay = ", currTradingDay[1,days])) %>% 
    .[, TradingDay := ymd(TradingDay)]

print(posOI)
## -----------------------------------------------------------------------------

## -----------------------------------------------------------------------------
## 交易信号表
signal <- mysqlQuery(
    db = accountDB,
    query = paste0(
        "select * from tradingSignal where TradingDay = ",
        lastTradingday[1,days])) %>% 
    .[, TradingDay := NULL] %>%
    .[, ":="(
        TradingDay = ymd(currTradingDay[1,days]),
        direction  = ifelse(direction == 1, 'long', 'short')
        )]
signalHO <- signal[strategyID == 'HOStrategy']
signalOI <- signal[strategyID == 'OIStrategy']

print(signalHO)
print(signalOI)
## -----------------------------------------------------------------------------

## -----------------------------------------------------------------------------
## 如果是已经开仓的信号，则不要重复开仓
## -------------------------------
if (nrow(posHOtoday) != 0 & nrow(signalHO) != 0) {
    for (i in 1:nrow(signalHO)) {
        tmp <- posHOtoday[InstrumentID == signalHO[i,InstrumentID] &
                          direction == signalHO[i,direction]]
        if (nrow(tmp) != 0) signalHO[i, volume := volume - tmp[1,volume]]
    }
    signalHO <- signalHO[volume > 0]
}

if (nrow(posOI) != 0 & nrow(signalOI) != 0) {
    for (i in 1:nrow(signalOI)) {
        tmp <- posOI[InstrumentID == signalOI[i,InstrumentID] &
                     direction == signalOI[i,direction]]
        if (nrow(tmp) != 0) signalOI[i, volume := volume - tmp[1,volume]]
    }
    signalOI <- signalOI[volume > 0]
}
## -----------------------------------------------------------------------------


## =============================================================================
## 处理　HOStrategy 内部的关系
## 1. 根据 posHO 与 signalHO 来
## -----------------------------------------------------------------------------

if (nrow(posHO) == 0 & nrow(signalHO) != 0) {
    ## -----------------
    ## 如果没有平仓的信息
    ## 则直接处理 交易信号
    ## -----------------
    res <- signalHO[, .(
        TradingDay, strategyID, InstrumentID,
        orderType = ifelse(direction == 'long','buy','short'),
        volume, stage = 'open'
        )]
    mysqlSend(db = accountDB,
              query = paste(
                    "delete from tradingOrders where strategyID =",
                    paste0("'","HOStrategy","'"),
                    "and stage =",
                    paste0("'","open","'"),
                    "and TradingDay =", currTradingDay[1,days]))
    mysqlWrite(db = accountDB, tbl = 'tradingOrders', data = res)
} else if (nrow(posHO) != 0) {
    ## ----------------------------
    ## 如果有持仓，需要计算与平仓的关系，
    ## 用来确定平仓的数量
    ## ----------------------------
    dtHO <- merge(posHO, signalHO, 
                  by = c('strategyID','InstrumentID','direction'), all = T)
    dtHO[, ":="(volume.x = ifelse(is.na(volume.x), 0, volume.x),
                volume.y = ifelse(is.na(volume.y), 0, volume.y))] %>%
        .[, deltaVolume := volume.x - volume.y]
    print(dtHO)

    ## ====================================================================== ##
    #                     pos    -    signal    =    delta      说明
    #             | >0    -1@signal   +1@signal   只平不开：平仓@dealta,转化交易日期
    # deltaVolume | =0    -1@pos  ==  +1@signal   不开不平：只转化交易日期,转化交易日期
    #             | <0    -1@pos      +1@pos      不平只开：开仓@delta
    ## ====================================================================== ##
    dtU <- dtHO[deltaVolume > 0]
    dtM <- dtHO[deltaVolume == 0]
    dtL <- dtHO[deltaVolume < 0]

    positionU <- positionM <- data.table()
    tradingU <- tradingL <- data.table()
    recordingU <- recordingM <- recordingL <- data.table()

    ## ----------------
    ## 持仓信息
    ## position
    ## 
    ## 需要进行平仓交易的
    ## trading
    ## 
    ## 需要改变日期的
    ## recording
    ## ----------------
    if (nrow(dtU) != 0) {
        positionU <- lapply(1:nrow(dtU), function(j){
            dtU[j, .(
                    strategyID, InstrumentID,
                    TradingDay = c(TradingDay.x, TradingDay.y),
                    direction, 
                    volume = c(abs(deltaVolume), volume.y)
                )] %>% 
            .[volume > 0]
        }) %>% rbindlist()

        tradingU <- dtU[, .(
            TradingDay = currTradingDay[1,days], 
            strategyID,
            InstrumentID,
            orderType = ifelse(direction == 'long','sell','cover'),
            volume = abs(deltaVolume),
            stage = 'close'
            )]

        recordingU <- lapply(1:nrow(dtU), function(j){
            dtU[j, .(
                TradingDay = currTradingDay[1,ymd(days)],
                tradeTime = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                strategyID, InstrumentID,
                direction = c(ifelse(direction == 'long', 'short', 'long'),
                              direction),
                offset = c('平仓','开仓'),
                volume = abs(volume.y),
                price = c(-1,1)
                )] %>% 
            .[volume > 0]
        }) %>% rbindlist()
    }

    if (nrow(dtM) != 0) {
        positionM <- lapply(1:nrow(dtM), function(j){
            dtM[j, .(
                    strategyID, InstrumentID,
                    TradingDay = TradingDay.y,
                    direction, volume = volume.x
                )]
        }) %>% rbindlist()

        recordingM <- lapply(1:nrow(dtM), function(j){
            dtM[j, .(
                TradingDay = currTradingDay[1,ymd(days)],
                tradeTime = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                strategyID, InstrumentID,
                direction = c(ifelse(direction == 'long', 'short', 'long'),
                              direction),
                offset = c('平仓','开仓'),
                volume = abs(volume.x),
                price = c(-1,1)
                )]
        }) %>% rbindlist()
    }

    if (nrow(dtL) != 0) {
        positionL <- lapply(1:nrow(dtL), function(j){
            dtL[j, .(
                    strategyID, InstrumentID,
                    TradingDay = TradingDay.y,
                    direction, volume = volume.x
                )] %>% 
            .[volume > 0]
        }) %>% rbindlist()

        tradingL <- dtL[, .(
            TradingDay = currTradingDay[1,days], 
            strategyID,
            InstrumentID,
            orderType = ifelse(direction == 'long','buy','short'),
            volume = abs(deltaVolume),
            stage = 'open'
            )]

        recordingL <- lapply(1:nrow(dtL), function(j){
            dtL[j, .(
                TradingDay = currTradingDay[1,ymd(days)],
                tradeTime = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                strategyID, InstrumentID,
                direction = c(ifelse(direction == 'long', 'short', 'long'),
                              direction),
                offset = c('平仓','开仓'),
                volume = abs(volume.x),
                price = c(-1,1)
                )] %>% 
            .[volume > 0]
        }) %>% rbindlist()
    }

    position <- list(positionU, positionM, positionL) %>% rbindlist()
    trading <- list(tradingU, tradingL) %>% rbindlist()
    recording <- list(recordingU, recordingM, recordingL) %>% rbindlist()

    ## ---------------------
    ## 把数据保存到 MySQL 数据库
    ## ---------------------
    if (nrow(positionU) != 0) {
        mysqlSend(db = accountDB,
                  query = paste(
                        "delete from positionInfo where strategyID =",
                        paste0("'","HOStrategy","'"),
                        "and TradingDay =", 
                        positionU[TradingDay < currTradingDay[1,ymd(days)],
                                  gsub('-','',unique(TradingDay))]))
    }
    mysqlWrite(db = accountDB, tbl = 'positionInfo', data = position)

    mysqlSend(db = accountDB,
              query = paste(
                    "delete from tradingOrders where strategyID =",
                    paste0("'","HOStrategy","'"),
                    "and TradingDay =", currTradingDay[1,days]))
    mysqlWrite(db = accountDB, tbl = 'tradingOrders', data = trading)

    if (nrow(recording) != 0) {
        for (j in 1:nrow(recording)) {
            mysqlSend(db = accountDB,
                      query = paste(
                            "delete from tradingInfo where strategyID =",
                            paste0("'","HOStrategy","'"),
                            "and TradingDay =", recording[j,TradingDay],
                            "and InstrumentID =", 
                            paste0("'", recording[j,InstrumentID], "'"),
                            "and direction =",
                            paste0("'", recording[j,direction], "'"),
                            "and offset =",
                            paste0("'", recording[j,offset], "'"),
                            "and volume =", recording[j,volume],
                            "and price =", recording[j,price]))
        }

        mysqlWrite(db = accountDB, tbl = 'tradingInfo', data = recording)
    }
}

# if (nrow(signalOI) == 0) {
#     stop("No OIStrategy tradingOrders.")
# }

## =============================================================================
## 处理　OIStrategy 内部的关系
## 1. 根据 posHO 与 signalHO 来
## -----------------------------------------------------------------------------

## -------------------
## HOStrategy 的平仓信息
## -------------------
closeHO <- mysqlQuery(
    db = accountDB,
    query = paste(
        "select * from tradingOrders
        where strategyID = 'HOStrategy'
        and stage = 'close'
        and TradingDay =", currTradingDay[1,days]
    )) %>% .[, TradingDay := ymd(TradingDay)] %>% 
    .[, direction := ifelse(orderType == 'sell', 'long','short')]

if (nrow(closeHO) == 0) {
    ## -----------------
    ## 如果没有平仓的信息
    ## 则直接处理 交易信号
    ## -----------------
    res <- signalOI[, .(
        TradingDay, strategyID, InstrumentID,
        orderType = ifelse(direction == 'long','buy','short'),
        volume, stage = 'open'
        )]
    mysqlSend(db = accountDB,
              query = paste(
                    "delete from tradingOrders where strategyID =",
                    paste0("'","OIStrategy","'"),
                    "and stage =",
                    paste0("'","open","'"),
                    "and TradingDay =", currTradingDay[1,days]))
    mysqlWrite(db = accountDB, tbl = 'tradingOrders', data = res)
} else {
    ## --------------------
    ## 如果有平仓的订单
    ## 则开始进行合并订单的处理
    ## --------------------
    dtOI <- merge(signalOI, closeHO,
        by = c('TradingDay','InstrumentID','direction'),
        all.x = T)
    dtOI[, ":="(volume.x = ifelse(is.na(volume.x), 0, volume.x),
                volume.y = ifelse(is.na(volume.y), 0, volume.y))] %>%
        .[, deltaVolume := volume.x - volume.y]
    print(dtOI)

    ## ====================================================================== ##
    #                     signal  -   orders    =    delta      说明
    #             | >0    +1@orders   -1@orders   只开不平：开仓@delta, 转化 strategyID
    # deltaVolume | =0    -1@signal   +1@signal   不开不平：只转化 strategyID
    #             | <0    +1@signal   -1@signal   只平不开：平仓@delta
    ## ====================================================================== ##
    dtU <- dtOI[deltaVolume > 0]
    dtM <- dtOI[deltaVolume == 0]
    dtL <- dtOI[deltaVolume < 0]

    positionU <- positionM <- data.table()
    tradingU <- tradingL <- data.table()
    recordingU <- recordingM <- recordingL <- data.table()

    ## ----------------
    ## 持仓信息
    ## position
    ## 
    ## 需要进行平仓交易的
    ## trading
    ## 
    ## 需要改变日期的
    ## recording
    ## ----------------
    if (nrow(dtU) != 0) {
        positionU <- lapply(1:nrow(dtU), function(j){
            dtU[j, .(
                    strategyID = strategyID.x, 
                    InstrumentID,
                    TradingDay,
                    direction, 
                    volume = volume.y
                )] %>% 
            .[volume > 0]
        }) %>% rbindlist()

        tradingU <- dtU[, .(
            TradingDay, 
            strategyID = strategyID.x,
            InstrumentID,
            orderType = ifelse(direction == 'long','buy','short'),
            volume = abs(deltaVolume),
            stage = 'open'
            )]

        recordingU <- lapply(1:nrow(dtU), function(j){
            dtU[j, .(
                TradingDay = currTradingDay[1,ymd(days)],
                tradeTime = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                strategyID = c(strategyID.y, strategyID.x), 
                InstrumentID,
                direction = c(ifelse(direction == 'long', 'short', 'long'),
                              direction),
                offset = c('平仓','开仓'),
                volume = abs(volume.y),
                price = c(-1,1)
                )] %>% 
            .[volume > 0]
        }) %>% rbindlist()
    }

    if (nrow(dtM) != 0) {
        positionM <- lapply(1:nrow(dtM), function(j){
            dtM[j, .(
                    strategyID = strategyID.x, 
                    InstrumentID,
                    TradingDay,
                    direction, volume = volume.x
                )]
        }) %>% rbindlist()

        recordingM <- lapply(1:nrow(dtM), function(j){
            dtM[j, .(
                TradingDay = currTradingDay[1,ymd(days)],
                tradeTime = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                strategyID = c(strategyID.y, strategyID.x), 
                InstrumentID,
                direction = c(ifelse(direction == 'long', 'short', 'long'),
                              direction),
                offset = c('平仓','开仓'),
                volume = abs(volume.x),
                price = c(-1,1)
                )]
        }) %>% rbindlist()
    }

    if (nrow(dtL) != 0) {
        positionL <- lapply(1:nrow(dtL), function(j){
            dtL[j, .(
                    strategyID = strategyID.x,
                    InstrumentID,
                    TradingDay,
                    direction, volume = volume.x
                )] %>% 
            .[volume > 0]
        }) %>% rbindlist()

        tradingL <- dtL[, .(
            TradingDay = currTradingDay[1,ymd(days)], 
            strategyID = strategyID.y, 
            InstrumentID,
            orderType = ifelse(direction == 'long','sell','cover'),
            volume = abs(deltaVolume),
            stage = 'close'
            )]

        recordingL <- lapply(1:nrow(dtL), function(j){
            dtL[j, .(
                TradingDay = currTradingDay[1,ymd(days)],
                tradeTime = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                strategyID = c(strategyID.y, strategyID.x), 
                InstrumentID,
                direction = c(ifelse(direction == 'long', 'sell', 'cover'),
                              direction),
                offset = c('平仓','开仓'),
                volume = abs(volume.x),
                price = c(-1,1)
                )] %>% 
            .[volume > 0]
        }) %>% rbindlist()
    }

    position <- list(positionU, positionM, positionL) %>% rbindlist()
    trading <- list(tradingU, tradingL) %>% rbindlist()
    recording <- list(recordingU, recordingM, recordingL) %>% rbindlist()

    if (nrow(position) != 0) {
        ## 获取 HO 的持仓信息
        positionHO <- mysqlQuery(
            db = accountDB,
            query = "select * from positionInfo
                    where strategyID = 'HOStrategy'
                    and TradingDay = (select min(TradingDay)
                                      from positionInfo
                                      where strategyID = 'HOStrategy')") %>% 
            .[, TradingDay := ymd(TradingDay)]
        ## 情况原来的持仓信息
        mysqlSend(
            db = accountDB,
            query = paste(
                "delete from positionInfo
                where strategyID = 'HOStrategy'
                and TradingDay =",
                positionHO[, gsub('-', '', unique(TradingDay))]
                ))

        for (i in 1:nrow(positionHO)) {
            id <- positionHO[i, InstrumentID]
            if (id %in% position[, InstrumentID]) {
                positionHO[i, volume := volume - 
                              position[InstrumentID == id,volume]]
            }
        }
        positionHO <- positionHO[volume > 0]

        res <- list(position, positionHO) %>% rbindlist()
        mysqlWrite(db = accountDB, tbl = 'positionInfo', data = res)
    }

    if (nrow(trading) != 0) {
        tradingHO <- trading[strategyID == 'HOStrategy']
        tradingOI <- trading[strategyID == 'OIStrategy']

        if (nrow(tradingOI) != 0) {
            mysqlWrite(db = accountDB, tbl = 'tradingOrders', data = tradingOI)
        }

        if (nrow(tradingHO) != 0) {
            ## 情况原来的持仓信息
            mysqlSend(
                db = accountDB,
                query = paste(
                    "delete from tradingOrders
                    where strategyID = 'HOStrategy'
                    and stage = 'close'
                    and TradingDay =",
                    closeHO[, gsub('-', '', unique(TradingDay))])
                )

            for (i in 1:nrow(closeHO)) {
                id <- closeHO[i, InstrumentID]
                if (id %in% tradingHO[,InstrumentID]) {
                    closeHO[i, volume := volume - tradingHO[InstrumentID == id, volume]]
                }
            }
            closeHO <- closeHO[volume > 0] %>% 
                .[, direction := NULL]
        }

        res <- list(tradingOI, closeHO) %>% rbindlist()
        mysqlWrite(db = accountDB, tbl = 'tradingOrders', data = res)
    }

    if (nrow(recording) != 0) {
        recordingHO <- recording[strategyID == 'HOStrategy']
        recordingOI <- recording[strategyID == 'OIStrategy']

        if (nrow(recordingOI) != 0) {
            mysqlWrite(db = accountDB, tbl = 'tradingInfo', data = recordingOI)
        }

        if (nrow(recordingHO) != 0) {
            tmpRecording <- mysqlQuery(
                db = accountDB,
                query = paste(
                    "select * from tradingInfo
                    where abs(price) = 1
                    and offset = '平仓'
                    and strategyID = 'HOStrategy'
                    and TradingDay =",
                    currTradingDay[1,days]
                    ))
        ## 情况原来的持仓信息
        mysqlSend(
            db = accountDB,
            query = paste(
                    "select * from tradingInfo
                    where abs(price) = 1
                    and offset = '平仓'
                    and strategyID = 'HOStrategy'
                    and TradingDay =",
                    currTradingDay[1,days])
            )

            if (nrow(tmpRecording) != 0) {
                for (i in 1:nrow(tmpRecording)) {
                    id <- tmpRecording[i,InstrumentID]
                    dirc <- tmpRecording[i,direction]
                    if (id %in% recordingHO[,InstrumentID] &
                        dirc %in% recordingHO[i,direction]) {
                        tmpRecording[i, volume := volume +
                            recordingHO[InstrumentID == id & direction == dirc,
                                        volume]]
                    }
                }
            }
            mysqlWrite(db = accountDB, tbl = 'tradingInfo', data = tmpRecording)
        }

    }

}
