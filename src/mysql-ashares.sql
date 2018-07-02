################################################################################
## 建立完整的基金交易数据库
################################################################################

CREATE DATABASE `fl` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
use fl;

################################################################################
## tradingSignal
## 记录策略的交易信号信号
## 1.tradingSignal 允许对外暴露, 接收从 researcher 传入的交易信号
##　2.利用　Rscripts 从 tradingSignal 生成　tradingOrder
################################################################################
create table tradingSignal(
    tradingDay      DATE            NOT NULL,  ## 交易日期
    strategyID      VARCHAR(50)     NOT NULL,  ## 策略ID
    classID         CHAR(10)                ,  ## 策略类型ID: cta, ashares
    exchID          CHAR(10)                ,  ## 金融市场ID, 股票: SSE, SZSE
    instrumentID    CHAR(30)        NOT NULL,  ## 合约代码(期货/股票/基金) 
    volume          BIGINT          NOT NULL,  ## 数量,手/股
    direction       CHAR(10)        NOT NULL,  ## 买卖方向:-1/+1
    param           FLOAT(10,5),               ## 如果需要其他参数的话
    PRIMARY KEY(tradingDay, strategyID, instrumentID, direction)
);


################################################################################
## tradingOrder
## 记录所有发出去的订单情况
## tradingOrder 不对外暴露，只传递给交易系统做订单
################################################################################
create table tradingOrder(
    tradingDay      DATE            NOT NULL,
    strategyID      VARCHAR(50)     NOT NULL,
    classID         CHAR(10)                ,  ## 策略类型ID: cta, ashares
    exchID          CHAR(10)                ,  ## 金融市场ID, 股票: SSE, SZSE
    instrumentID    CHAR(30)        NOT NULL,
    orderType       CHAR(10)        NOT NULL,  ## 期货：buy, sell, short, cover
                                               ## 股票：buy, sell
    volume          BIGINT          NOT NULL,  
    stage           CHAR(10)        NOT NULL,  ## 开盘：starting, 收盘：ending
    PRIMARY KEY(tradingDay, strategyID, instrumentID, orderType, stage)
);




create table accountInfo(
    accountID       VARCHAR(50)     NOT NULL,    ## 账户
    TradingDay      DATE            NOT NULL,    ## 交易日期
    updateTime      DATETIME        NOT NULL,    ## 更新时间
    ## ---------------------------
    nav             DECIMAL(10,5),  ## 单位净值
    chgpct          DECIMAL(10,5),  ## 净值变动
    ## ---------------------------
    preBalance      DECIMAL(15,3),  ## 账户昨日资产
    deposit         DECIMAL(15,3),  ##　账户入金
    withdraw        DECIMAL(15,3),  ## 账户出金
    balance         DECIMAL(15,3),  ##　账户今日资产
    ## ---------------------------
    margin          DECIMAL(15,3),  ## 保证金
    available       DECIMAL(15,3),  ## 可用资金
    value           DECIMAL(15,3),  ## 合约价值
    marginPct       DECIMAL(15,3),  ## 保证金比例
    ## ---------------------------
    ## ---------------------------
    positionProfit  DECIMAL(15,3),  ## 持仓盈亏 
    closeProfit     DECIMAL(15,3),  ## 平仓盈亏
    profit          DECIMAL(15,3),  ## 盈亏
    commission      DECIMAL(15,3),  ## 手续费
    ## ---------------------------
    flowCapital     DECIMAL(15,3),  ## 流动（理财）资产
    banking         DECIMAL(15,3),  ## (银行)现金存款
    fee             DECIMAL(15,3),  ## 托管收取的各种费用
    ## ---------------------------
    asset           DECIMAL(15,3),  ## 总资产 = balance + flowCapital + currency + fee
    shares          BIGINT,         ## 总份额
    PRIMARY KEY(accountID, TradingDay)
);


create table positionInfo(
    strategyID      VARCHAR(50)     NOT NULL,
    instrumentID    VARCHAR(30)     NOT NULL,
    TradingDay      DATE            NOT NULL,
    direction       VARCHAR(20)     NOT NULL,
    volume          INT             NULL,
    iRIMARY KEY(strategyID, InstrumentID, TradingDay, direction)
);

################################################################################
## fl.tradingIndo
## 策略交易历史情况
################################################################################
create table tradingInfo(
    strategyID      VARCHAR(50)     NOT NULL,
    instrumentID    VARCHAR(30)     NOT NULL,
    TradingDay      DATE            NOT NULL,
    tradeTime       DATETIME        NOT NULL,
    direction       VARCHAR(20)     NOT NULL,
    offset          VARCHAR(20)     NOT NULL,
    volume          INT             NOT NULL,
    price           DECIMAL(15,5)   NOT NULL
    i- PRIMARY KEY(strategyID, InstrumentID, TradingDay, tradeTime, direction, offset)
    i- PRIMARY KEY(strategyID, InstrumentID, TradingDay, tradeTime, direction, offset)
);

## orderTime: 下单时间
## offset: 开仓, 平仓


################################################################################
## failedInfo
## 策略交易失败情况
################################################################################
create table failedInfo(
    strategyID      VARCHAR(50)      NOT NULL,
    instrumentID    VARCHAR(30)      NOT NULL,
    TradingDay      DATE             NOT NULL,
    direction       VARCHAR(20)      NOT NULL,
    offset          VARCHAR(20)      NOT NULL,
    volume          INT              NOT NULL,
    iRIMARY KEY(strategyID, InstrumentID, TradingDay, direction, offset)
);

################################################################################
## orderInfo
## 记录所有发出去的订单情况
################################################################################
create table orderInfo(
    TradingDay      DATE            NOT NULL,
    strategyID      VARCHAR(50)     NOT NULL,
    vtOrderID       VARCHAR(50)     NOT NULL,    
    instrumentID    VARCHAR(30)     NOT NULL,
    orderTime       TIME            NOT NULL,
    status          VARCHAR(50)     ,
    direction       VARCHAR(20)     ,
    cancelTime      VARCHAR(100)    ,
    tradedVolume    INT          ,
    frontID         SMALLINT     ,
    sessionID       BIGINT       ,
    offset          VARCHAR(50)     ,
    price           DECIMAL(15,5) ,
    totalVolume     BIGINT       ,
    iRIMARY KEY(TradingDay, strategyID, vtOrderID, InstrumentID, status)
);


################################################################################
## tradingOrders
## 记录所有发出去的订单情况
################################################################################
create table tradingOrders(
    TradingDay      DATE            NOT NULL,
    strategyID      VARCHAR(50)     NOT NULL,
    instrumentID    VARCHAR(30)     NOT NULL,
    orderType       VARCHAR(50)     NOT NULL,
    volume          BIGINT          NOT NULL,
    stage           VARCHAR(20)     NOT NULL,
    iRIMARY KEY(TradingDay, strategyID, InstrumentID, orderType, stage)
);


################################################################################
## workingInfo
## 记录正在进行的订单
################################################################################
create table workingInfo(
    TradingDay      DATE            NOT NULL,
    strategyID      VARCHAR(50)     NOT NULL,
    vtSymbol        VARCHAR(20)     NOT NULL,
    vtOrderIDList   text            NOT NULL,   
    orderType       VARCHAR(50)     NOT NULL,
    volume          BIGINT          NOT NULL,
    stage           VARCHAR(20)     NOT NULL, 
    PRIMARY KEY(TradingDay, strategyID, vtSymbol, orderType, stage)
);

################################################################################
## pnl
## 记录正在进行的订单
################################################################################
create table pnl(
    TradingDay      DATE            NOT NULL,
    strategyID      VARCHAR(50)     NOT NULL,
    instrumentID    VARCHAR(30)     NOT NULL,
    pnl             DECIMAL(15,3),
    iRIMARY KEY(TradingDay, strategyID, InstrumentID)
);




################################################################################
## report_account
## 记录策略信号
################################################################################



################################################################################
## nav
## 记录基金净值
################################################################################
create table nav(
    TradingDay      DATE          NOT NULL,
    Futures         DECIMAL(15,5) NOT NULL,
    Currency        DECIMAL(15,5) ,
    Bank            DECIMAL(15,5) ,
    Assets          DECIMAL(15,5) NOT NULL,
    Shares          BIGINT        NOT NULL,
    NAV             DECIMAL(15,6) NOT NULL,
    GrowthRate      DECIMAL(10,5) NOT NULL,
    Remarks         text(1000)
);


################################################################################
## UpperLower
## 记录涨跌停下单平仓的信息
################################################################################
create table UpperLowerInfo(
    TradingDay      DATE         NOT NULL,
    strategyID      CHAR(50)     NOT NULL,
    instrumentID    VARCHAR(30)  NOT NULL,
    vtOrderIDList   VARCHAR(100)     NOT NULL,
    direction       VARCHAR(20),
    volume          INT          
);


################################################################################
## winner
## 记录 止盈平仓单 的信息
################################################################################
create table winnerInfo(
    TradingDay      DATE         NOT NULL,
    strategyID      CHAR(50)     NOT NULL,
    instrumentID    VARCHAR(30)  NOT NULL,
    vtOrderIDList   VARCHAR(100)     NOT NULL,
    direction       VARCHAR(20),
    volume          INT          
);


################################################################################
## fee
## 记录基金各项手续费
################################################################################
create table fee(
    TradingDay      DATE          NOT NULL,
    Amount          DECIMAL(10,5) NOT NULL,
    Remarks         text(1000)
);

################################################################################
## lastTickInfo
## 保存最新的 tick 级别的数据
################################################################################
create table lastTickInfo(
    TradingDay      DATE            NOT NULL,
    updateTime      DATETIME        NOT NULL,
    ## -------------------------------------------------------------------------
    vtSymbol        VARCHAR(30)     NOT NULL,
    lastPrice       DECIMAL(10,3)   NOT NULL,
    volume          BIGINT,
    turnover        DECIMAL(30,3),
    openPrice       DECIMAL(10,3),
    highestPrice    DECIMAL(10,3),
    lowestPrice     DECIMAL(10,3),
    bidPrice1       DECIMAL(10,3),
    askPrice1       DECIMAL(10,3),
    bidVolume1      BIGINT,
    askVolume1      BIGINT,
    ## ---------------------------
    upperLimit      DECIMAL(10,3),
    lowerLimit      DECIMAL(10,3),
    PRIMARY KEY(TradingDay, vtSymbol)
);


################################################################################
## funding
## 记录基金申购、赎回记录
################################################################################
create table funding(
    TradingDay      DATE            NOT NULL,
    ## -------------------------------------------------------------------------
    capital         DECIMAL(15,2),   ## 购买资金
    price           DECIMAL(10,6),   ## 购买时的净值，类似成本
    shares          DECIMAL(15,2),   ## 购买份额   
    ## ---------------------------
    investor        VARCHAR(30) NULL     ## 客户
    ## ---------------------------
);



-- alter table accountInfo modify nav decimal(10,5) after updateTime;
-- alter table accountInfo add column chgpct decimal(10,5) after nav;
