# encoding: UTF-8

"""
OIStrategy 策略的交易实现
＠william
"""
from __future__ import division
import os,sys,subprocess

from vnpy.trader.vtObject import VtBarData
from vnpy.trader.vtConstant import EMPTY_STRING
from vnpy.trader.app.ctaStrategy.ctaTemplate import (CtaTemplate, 
                                                     BarGenerator)
from vnpy.trader.vtEvent import *
from vnpy.trader import vtFunction
## -----------------------------------------------------------------------------
from logging import INFO, ERROR
import pandas as pd
from pandas.io import sql

from datetime import datetime,time,timedelta
import time
import pprint
from copy import copy
import math,random
import re,ast,csv,ujson
## -----------------------------------------------------------------------------
from vnpy.trader.vtGlobal import globalSetting

########################################################################
class OIStrategy(CtaTemplate):
    """ oiRank 交易策略 """
    ############################################################################
    ## william
    ## 策略类的名称和作者
    ## -------------------------------------------------------------------------
    name         = 'OiRank'
    className    = 'OIStrategy'
    strategyID   = className
    author       = 'Lin HuanGeng'
    ############################################################################
    
    ## =========================================================================
    ## william
    ## 以下是我的修改
    ############################################################################
    ## -------------------------------------------------------------------------
    ## 各种控制条件
    ## 策略的基本变量，由引擎管理
    trading      = False                    # 是否启动交易，由引擎管理
    tradingStart = False                    # 开盘启动交易
    tradingStartSplit = False
    tradingBetween = False
    tradingEnd   = False                    # 收盘开启交易
    tickTimer    = {}                  # 计时器, 用于记录单个合约发单的间隔时间
    ## -------------------------------------------------------------------------

    ## -------------------------------------------------------------------------
    ## 各种交易订单的合成
    ## 交易订单存放位置
    ## 字典格式如下
    ## 1. vtSymbol
    ## 2. direction: buy, sell, short, cover
    ## 3. volume
    ## 4. TradingDay
    ## 5. vtOrderIDList
    ## -------------------------------------------------------------------------
    tradingOrders           = {}       # 单日的订单
    tradingOrdersOpen       = {}       # 当日开盘的订单
    tradingOrdersClose      = {}       # 当日收盘的订单
    tradingOrdersUpperLower = {}       # 以涨跌停价格的订单
    tradingOrdersUpperLowerCum = {}    # 以涨跌停价格的订单 ==> 开盘前1分钟先累计
    tradingOrdersFailedInfo = {}       # 上一个交易日没有完成的订单,需要优先处理
    tradingOrdersWinner     = {}       # 止盈平仓单
    ## -------------------------------------------------------------------------
    tradedOrders            = {}       # 当日订单完成的情况
    tradedOrdersOpen        = {}       # 当日开盘完成的已订单
    tradedOrdersClose       = {}       # 当日收盘完成的已订单
    tradedOrdersFailedInfo  = {}       # 昨天未成交订单的已交易订单
    tradedOrdersUpperLower  = {}       # 已经成交的涨跌停订单
    tradedOrdersWinner      = {}       # 已经成交的止盈单
    ## -------------------------------------------------------------------------

    ## -------------------------------------------------------------------------
    ## 各种交易订单的合成
    ## -------------------------------------------------------------------------
    vtOrderIDList           = []       # 保存委托代码的列表
    vtOrderIDListOpen       = []       # 开盘的订单
    vtOrderIDListOpenSplit   = []       # 开盘的拆单
    vtOrderIDListClose      = []       # 收盘的订单
    vtOrderIDListFailedInfo = []       # 失败的合约订单存储
    vtOrderIDListUpperLower = []       # 涨跌停价格成交的订单
    vtOrderIDListUpperLowerCum = []    # 涨跌停价格成交的订单
    vtOrderIDListUpperLowerTempCum = []    # 涨跌停价格成交的订单
    vtOrderIDListWinner     = []       # 止盈平仓单
    vtOrderIDListTempWinner = []       # 止盈平仓单
    vtOrderIDListAll        = []       # 所有订单集合

    ## 是否使用 盈利平仓 的策略
    WINNER_STRATEGY = []
    ## -------------------------------------------------------------------------

    #----------------------------------------------------------------------
    def __init__(self, ctaEngine, setting):
        """Constructor"""
        ## 从　ctaEngine 继承所有属性和方法
        super(OIStrategy, self).__init__(ctaEngine, setting)

        ## =====================================================================
        ## 子订单的拆单比例实现
        if self.ctaEngine.mainEngine.initialCapital >= 0.8e7:
            self.subOrdersLevel = {
                              'level0':{'weight': 0.20, 'deltaTick': 0},
                              'level1':{'weight': 0.45, 'deltaTick': 1},
                              'level2':{'weight': 0.35, 'deltaTick': 2}
                              }
        else:
            self.subOrdersLevel = {
                              'level0':{'weight': 0.30, 'deltaTick': 0},
                              'level1':{'weight': 0.70, 'deltaTick': 1},
                              'level2':{'weight': 0, 'deltaTick': 2}
                             }
        self.totalOrderLevel = 1 + (len(self.subOrdersLevel) - 1) * 2
        self.realOrderLevel = len(
            [k for k in self.subOrdersLevel.keys() 
                   if self.subOrdersLevel[k]['weight'] != 0]
            )
        ## =====================================================================

        ## =====================================================================
        self.openDiscount  = self.ctaEngine.mainEngine.openDiscountOI
        self.closeDiscount = self.ctaEngine.mainEngine.closeDiscountOI

        self.openAddTick   = self.ctaEngine.mainEngine.openAddTickOI
        self.closeAddTick  = self.ctaEngine.mainEngine.closeAddTickOI
        ## =====================================================================

        ## =====================================================================
        # 创建K线合成器对象
        self.bg = BarGenerator(self.onBar)
        ## =====================================================================

        ## =====================================================================
        ## 交易时点
        self.tradingStartCounter = 0
        self.tradingOpenHour    = [21,9]
        self.tradingOpenMinute1 = 0
        self.tradingOpenMinute2 = 10

        self.tradingCloseHour    = 14
        self.tradingCloseMinute1 = 50
        self.tradingCloseMinute2 = 59
        self.accountID = globalSetting.accountID

        if self.ctaEngine.mainEngine.initialCapital >= 1.5e7:
            self.randomNo = 10 + random.randint(-3,3)    ## 随机间隔多少秒再下单
        elif self.ctaEngine.mainEngine.initialCapital >= 1e7:
            self.randomNo = 15 + random.randint(-3,3)    ## 随机间隔多少秒再下单
        elif self.ctaEngine.mainEngine.initialCapital >= 8e6:
            self.randomNo = 20 + random.randint(-5,5)    ## 随机间隔多少秒再下单
        elif self.ctaEngine.mainEngine.initialCapital >= 5e6:
            self.randomNo = 30 + random.randint(-5,5)    ## 随机间隔多少秒再下单
        else:
            self.randomNo = 45 + random.randint(-5,5)    ## 随机间隔多少秒再下单
        ## =====================================================================

        ## ===================================================================== 
        ## william
        # 注意策略类中的可变对象属性（通常是list和dict等），在策略初始化时需要重新创建，
        # 否则会出现多个策略实例之间数据共享的情况，有可能导致潜在的策略逻辑错误风险，
        # 策略类中的这些可变对象属性可以选择不写，全都放在__init__下面，写主要是为了阅读
        # 策略时方便（更多是个编程习惯的选择） 
        # 
        ## ===================================================================== 

        ## =====================================================================
        ## 上一个交易日未成交订单
        self.failedInfo = vtFunction.dbMySQLQuery(
            self.ctaEngine.mainEngine.dataBase,
            """
            SELECT *
            FROM failedInfo
            WHERE strategyID = '%s'
            """ %(self.strategyID))
        self.processFailedInfo(self.failedInfo)

        ## ---------------------------------------------------------------------
        ## 查看当日已经交易的订单
        ## ---------------------------------------------------------------------
        # self.tradingInfo = vtFunction.dbMySQLQuery(
        #     self.ctaEngine.mainEngine.dataBase,
        #     """
        #     SELECT *
        #     FROM tradingInfo
        #     WHERE strategyID = '%s'
        #     AND TradingDay = '%s'
        #     """ %(self.strategyID, self.ctaEngine.tradingDay))

        ## =====================================================================
        ## 涨跌停的订单
        temp = vtFunction.dbMySQLQuery(
            self.ctaEngine.mainEngine.dataBase,
            """
            SELECT *
            FROM UpperLowerInfo
            WHERE strategyID = '%s'
            AND TradingDay = '%s'
            """ %(self.strategyID, self.ctaEngine.tradingDate))
        if len(temp):
            for i in xrange(len(temp)):
                self.vtOrderIDListUpperLower.extend(ast.literal_eval(temp.ix[i,'vtOrderIDList']))
        ## =====================================================================
        
        ## =====================================================================
        ## 涨跌停的订单
        tempCum = vtFunction.dbMySQLQuery(
            self.ctaEngine.mainEngine.dataBase,
            """
            SELECT *
            FROM workingInfo
            WHERE strategyID = '%s'
            AND TradingDay = '%s'
            AND stage = 'ul'
            """ %(self.strategyID, self.ctaEngine.tradingDate))
        if len(tempCum):
            for i in xrange(len(tempCum)):
                ## -------------------------------------------------------------
                self.vtOrderIDListUpperLowerTempCum.extend(
                    ast.literal_eval(tempCum.ix[i,'vtOrderIDList']))
                ## -------------------------------------------------------------
                tempKey = tempCum.loc[i, 'vtSymbol'] + '-' + tempCum.loc[i, 'orderType']

                self.tradingOrdersUpperLowerCum[tempKey] = {
                        'vtSymbol'      : tempCum.loc[i, 'vtSymbol'],
                        'direction'     : tempCum.loc[i, 'orderType'],
                        'volume'        : tempCum.loc[i, 'volume'],
                        'TradingDay'    : tempCum.loc[i, 'TradingDay'],
                        'vtOrderIDList' : ast.literal_eval(tempCum.loc[i, 'vtOrderIDList'])
                        }
        ## =====================================================================


        ## =====================================================================
        ## 涨跌停的订单
        tempWinner = vtFunction.dbMySQLQuery(
            self.ctaEngine.mainEngine.dataBase,
            """
            SELECT *
            FROM workingInfo
            WHERE strategyID = '%s'
            AND TradingDay = '%s'
            AND stage = 'winner'
            """ %(self.strategyID, self.ctaEngine.tradingDate))
        if len(tempWinner):
            for i in xrange(len(tempWinner)):
                self.vtOrderIDListTempWinner.extend(ast.literal_eval(tempWinner.ix[i,'vtOrderIDList']))
        
        ## =====================================================================
        mysqlpositionInfo = vtFunction.dbMySQLQuery(
            self.ctaEngine.mainEngine.dataBase,
            """
            SELECT *
            FROM positionInfo
            WHERE strategyID = '%s'
            """ %(self.strategyID))
        
        if len(mysqlpositionInfo):
            for i in xrange(len(mysqlpositionInfo)):
                ## -------------------------------------------------
                if mysqlpositionInfo.at[i, 'direction'] == 'long':
                    tempDirection = 'sell'
                elif mysqlpositionInfo.at[i, 'direction'] == 'short':
                    tempDirection = 'cover'
                ## -------------------------------------------------
                id = mysqlpositionInfo.at[i, 'InstrumentID']
                tempKey = id + '-' + tempDirection
                x = tempWinner.loc[tempWinner.vtSymbol == id]

                if len(x):
                    ## 如果已经有了下单的
                    y = mysqlpositionInfo.at[i, 'volume'] - int(x['volume'].values)
                    if y > 0:
                        tempVolume = y
                    else:
                        tempVolume = 0
                else:
                    ##　如果没有下单
                    tempVolume = mysqlpositionInfo.at[i, 'volume']

                if tempVolume:
                    self.tradingOrdersWinner[tempKey] = {
                            'vtSymbol'      : id,
                            'direction'     : tempDirection,
                            'volume'        : tempVolume,
                            'TradingDay'    : mysqlpositionInfo.at[i, 'TradingDay'],
                            'vtOrderIDList' : []
                            }
        ## =====================================================================

        ## =====================================================================
        ## 止盈平仓参数
        self.winnerParam = {}
        tradingSignal = vtFunction.fetchMySQL(
            db = self.accountID,
            query = """select InstrumentID as vtSymbol,direction,volume,param 
                       from tradingSignal 
                       where TradingDay = %s and strategyID = '%s'""" 
                       %(self.ctaEngine.lastTradingDay, self.strategyID))
        if len(tradingSignal):
            for i in xrange(len(tradingSignal)):
                k = tradingSignal.at[i, 'vtSymbol']
                self.winnerParam[k] = dict(tradingSignal.iloc[i])
                self.winnerParam[k]['param'] = float(self.winnerParam[k]['param'])
                self.winnerParam[k]['priceTick'] = self.ctaEngine.tickInfo[k]['priceTick']
        ## =====================================================================

        ########################################################################
        ## 是不是需要保存 Bar 数据
        # self.DATA_PATH    = os.path.normpath(os.path.join(
        #                     globalSetting().vtSetting['DATA_PATH'], 
        #                     globalSetting.accountID, 'BarData'))
        # self.dataFile     = os.path.join(self.DATA_PATH,(str(self.tradingDay) + '.csv'))
        # if not os.path.exists(self.dataFile):
        #     with open(self.dataFile, 'w') as f:
        #         wr = csv.writer(f)
        #         wr.writerow(self.barHeader)
        #     f.close()
        ########################################################################

        ########################################################################
        ## william
        # 注册事件监听
        self.registerEvent()
        ########################################################################

    #---------------------------------------------------------------------------
    def onInit(self):
        """初始化策略（必须由用户继承实现）"""
        self.writeCtaLog(u'%s策略初始化' %self.name)
        ## =====================================================================
        if self.ctaEngine.mainEngine.multiStrategy:
            self.tradingOrdersOpen = self.fetchTradingOrders(stage = 'open')
            self.updateTradingOrdersVtOrderID(tradingOrders = self.tradingOrdersOpen,
                                              stage = 'open')
            self.updateVtOrderIDList('open')
            if len(self.tradingOrdersOpen):
                for k in self.tradingOrdersOpen.keys():
                    self.tradingOrdersOpen[k]['lastTimer'] -= timedelta(seconds = 60)
        else:
            pass
        ## =====================================================================

        ## ---------------------------------------------------------------------
        if self.tradingOrdersFailedInfo:
            self.writeCtaLog("昨日失败需要执行的订单\n%s\n%s\n%s" 
                %('-'*80,
                  pprint.pformat(self.tradingOrdersFailedInfo),
                  '-'*80))
        if self.tradingOrdersOpen:
            self.writeCtaLog("当日需要执行的开仓订单\n%s\n%s\n%s" 
                %('-'*80,
                  pprint.pformat(self.tradingOrdersOpen),
                  '-'*80))
        ## =====================================================================

        ## =====================================================================
        ## ---------------------------------------------------------------------
        try:
            self.positionContracts = self.ctaEngine.mainEngine.dataEngine.positionInfo.keys()
        except:
            self.positionContracts = []
        tempSymbolList = list(set(self.tradingOrdersOpen[k]['vtSymbol'] 
                                       for k in self.tradingOrdersOpen.keys()) | 
                              set(self.ctaEngine.allContracts) |
                              set(self.positionContracts))
        for symbol in tempSymbolList:
            if symbol not in self.tickTimer.keys():
                self.tickTimer[symbol] = datetime.now()
        ## =====================================================================
        self.updateTradingStatus()
        self.putEvent()
        ## =====================================================================

    #---------------------------------------------------------------------------
    def onTick(self, tick):
        """收到行情TICK推送（必须由用户继承实现）"""
        ## =====================================================================
        if not self.trading:
            return 
        if tick.datetime <= (datetime.now() - timedelta(seconds=5)):
            return
        # elif self.accountID in self.WINNER_STRATEGY:
        #     self.bg.updateTick(tick)
        # elif ((datetime.now() - self.tickTimer[tick.vtSymbol]).seconds < 1):
        #     return
        ## =====================================================================

        cdef:
            char* id = tick.vtSymbol
            int i
            char* x
            list vtSymbolOpen
            str tempPriceType
            int h = datetime.now().hour
            int m = datetime.now().minute

        ## =====================================================================
        if ((self.tradingStart and not self.tradingEnd) and 
            id in [self.tradingOrdersOpen[k]['vtSymbol'] 
                        for k in self.tradingOrdersOpen.keys()]):
            ####################################################################

            ## -----------------------------------------------------------------
            ## 第一个数据进来就直接下单，不用再等后面的数据
            if self.tradingStartCounter <= 30:
                self.tradingStartCounter += 1
                ## ---------------------------------------------------------------------------------
                vtSymbolOpen = [j for j in self.ctaEngine.lastTickDict.keys()
                                   if j in [self.tradingOrdersOpen[k]['vtSymbol'] 
                                             for k in self.tradingOrdersOpen.keys()]]
                ## ---------------------------------------------------------------------------------
                for i in xrange(self.realOrderLevel):
                    for x in vtSymbolOpen:
                        ## -----------------------------------------------------
                        exchange = self.ctaEngine.lastTickDict[x]['exchange']
                        if not self.ctaEngine.exchangeTradingStatus[exchange]:
                            self.writeCtaLog(u'%s 未到交易时间.' %exchange,
                                             logLevel = ERROR) 
                            continue
                        ## -----------------------------------------------------
                        self.prepareTradingOrderSplit(
                            vtSymbol      = x,
                            tradingOrders = self.tradingOrdersOpen,
                            orderIDList   = self.vtOrderIDListOpen,
                            priceType     = 'limit',
                            discount      = self.openDiscount)
            else:
                self.prepareTradingOrderSplit(
                    vtSymbol      = id,
                    tradingOrders = self.tradingOrdersOpen,
                    orderIDList   = self.vtOrderIDListOpen,
                    priceType     = 'limit',
                    discount      = self.openDiscount)
            ## -----------------------------------------------------------------
           
            # if self.tradingStartSplit:            
            #     tempOrderIDList = self.vtOrderIDListOpenSplit
            # elif self.tradingStart:
            #     tempOrderIDList = self.vtOrderIDListOpen

            # self.prepareSplit(
            #     vtSymbol = id,
            #     tradingOrders = self.tradingOrdersOpen,
            #     orderIDList = tempOrderIDList)

        ## =====================================================================

        ## =====================================================================
        elif ((self.tradingBetween or self.tradingEnd) and 
            id in [self.tradingOrdersClose[k]['vtSymbol'] 
                        for k in self.tradingOrdersClose.keys()]):
            if self.tradingBetween:
                ## ----------------------------
                if (id[0:2] not in ['bu','cs','pb','c1','a1','b1',
                                    'v1','y1','l1','p1',
                                    'FG','RM','OI','SM','SR','SF'] and 
                    m < self.tradingCloseMinute2-3):
                    tempPriceType = 'best'
                    tempAddTick   = -1
                else:
                    tempPriceType = 'last'
                    tempAddTick   = 0
                ## ----------------------------
                self.prepareTradingOrderSplit(
                    vtSymbol      = id,
                    tradingOrders = self.tradingOrdersClose,
                    orderIDList   = self.vtOrderIDListClose,
                    priceType     = tempPriceType,
                    addTick       = self.closeAddTick + tempAddTick)
                ## ----------------------------
                # self.prepareSplit(
                #     vtSymbol      = id,
                #     tradingOrders = self.tradingOrdersClose,
                #     orderIDList   = self.vtOrderIDListClose,
                #     priceType     = tempPriceType,
                #     addTick       = self.closeAddTick + tempAddTick)
            elif self.tradingEnd:
                self.prepareTradingOrder(
                    vtSymbol      = id,
                    tradingOrders = self.tradingOrdersClose,
                    orderIDList   = self.vtOrderIDListClose,
                    priceType     = 'chasing',
                    addTick       = 2)
        ## =====================================================================

        # =====================================================================
        if (self.accountID not in self.WINNER_STRATEGY and 
            (self.tradingStart and not (h in [9,21] and m < 2)) and 
            id in [self.tradingOrdersUpperLowerCum[k]['vtSymbol'] 
                             for k in self.tradingOrdersUpperLowerCum.keys()]):
            ## -----------------------------------------------------------------
            ## -------------------------------------------------------------
            ## 1. 「开多」 --> sell@upper
            ## 2. 「开空」 --> cover@lower
            tempDirection = [v['direction'] for v in self.tradingOrdersUpperLowerCum.values() 
                                             if v['vtSymbol'] == id][0]
            if tempDirection == 'sell':
                tempPriceType = 'upper'
            elif tempDirection == 'cover':
                tempPriceType = 'lower'
            ## -------------------------------------------------------------
            self.prepareTradingOrder(
                vtSymbol      = id,
                tradingOrders = self.tradingOrdersUpperLowerCum,
                orderIDList   = self.vtOrderIDListUpperLowerCum,
                priceType     = tempPriceType,
                addTick       = 0)
            # -----------------------------------------------------------------
        # =====================================================================

        ########################################################################
        ## william
        ## =====================================================================
        if self.tradingOrdersFailedInfo and self.tradingStart:
            self.prepareTradingOrder(
                vtSymbol      = id,
                tradingOrders = self.tradingOrdersFailedInfo,
                orderIDList   = self.vtOrderIDListFailedInfo,
                priceType     = 'chasing')
        ## =====================================================================

    ## =========================================================================
    ## william
    ## 处理 bar 数据
    ## -------------------------------------------------------------------------
    def onBar(self, bar):
        """Bar 数据进来后触发事件"""
        ## --------------------------
        ## 从 ctaTemplate 获取 Bar 数据
        ## 然后触发条件
        ## --------------------------
        
        # data = [bar.__dict__[k] for k in self.barHeader]  
        # print data
        # ## ---------------------------------
        # with open(self.dataFile, 'a') as f:
        #     wr = csv.writer(f)
        #     wr.writerow(data)
        # ## ---------------------------------

        ## =====================================================================
        cdef str id = bar.vtSymbol
        
        if ( (not self.tradingStart) or 
             (id not in [self.tradingOrdersWinner[k]['vtSymbol'] 
                      for k in self.tradingOrdersWinner.keys()]) ):
            return

        high = self.ctaEngine.lastTickDict[id]['lowestPrice'] + self.winnerParam[id]['param'] * self.winnerParam[id]['priceTick']
        low = self.ctaEngine.lastTickDict[id]['highestPrice'] - self.winnerParam[id]['param'] * self.winnerParam[id]['priceTick']

        if ( (self.winnerParam[id]['direction'] == '1' and (bar.high >= high)) or 
             (self.winnerParam[id]['direction'] == '-1' and (bar.low <= low)) ):
            self.writeCtaLog(u'发送 Winner Order: %s' %id)
            tempDirection = [v['direction'] for v in self.tradingOrdersWinner.values() 
                                            if v['vtSymbol'] == id][0]
            ## -------------------------------------------------------------
            self.prepareTradingOrder(
                vtSymbol      = id,
                tradingOrders = self.tradingOrdersWinner,
                orderIDList   = self.vtOrderIDListWinner,
                priceType     = 'limit',
                price         = bar.close)
            ## -----------------------------------------------------------------
        ## =====================================================================


    #+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    def onOrder(self, order):
        """收到委托变化推送（必须由用户继承实现）"""
        pass

    #----------------------------------------------------------------------
    def onTrade(self, trade):
        """处理成交订单"""
        ## ---------------------------------------------------------------------
        cdef:
            str tempDirection
            str tempKey
            str tempPriceType
            char* vtOrderID = trade.vtOrderID
            char* vtSymbol = trade.vtSymbol

        ## =====================================================================
        ## 0. 数据预处理
        ## =====================================================================
        self.stratTrade = copy(trade.__dict__)
        self.stratTrade['InstrumentID'] = vtSymbol
        self.stratTrade['strategyID']   = self.strategyID
        self.stratTrade['tradeTime']    = datetime.now().strftime('%Y-%m-%d') + " " + self.stratTrade['tradeTime']
        self.stratTrade['TradingDay']   = self.ctaEngine.tradingDate

        ## ---------------------------------------------------------------------
        if self.stratTrade['offset'] == u'开仓':
            tempOffset = u'开仓'.encode('UTF-8')
            if self.stratTrade['direction'] == u'多':
                self.stratTrade['direction'] = 'long'
                tempDirection = 'buy'
            elif self.stratTrade['direction'] == u'空':
                self.stratTrade['direction'] = 'short'
                tempDirection = 'short'
        elif self.stratTrade['offset'] in [u'平仓', u'平昨', u'平今']:
            tempOffset = u'平仓'.encode('UTF-8')
            if self.stratTrade['direction'] == u'多':
                self.stratTrade['direction'] = 'long'
                tempDirection = 'cover'
            elif self.stratTrade['direction'] == u'空':
                self.stratTrade['direction'] = 'short'
                tempDirection = 'sell'
        ## ---------------------------------------------------------------------

        ## ---------------------------------------------------------------------
        tempKey = (vtSymbol + '-' + tempDirection).encode('ascii','ignore')
        ## ---------------------------------------------------------------------

        ########################################################################
        ## william
        ## 更新数量
        ## 更新交易日期
        if (vtOrderID in self.vtOrderIDListOpen + self.vtOrderIDListOpenSplit and 
            tempKey in self.tradingOrdersOpen.keys()):
            # ------------------------------------------------------------------
            self.tradingOrdersOpen[tempKey]['volume'] -= self.stratTrade['volume']
            if self.tradingOrdersOpen[tempKey]['volume'] == 0:
                self.tradingOrdersOpen.pop(tempKey, None)
                self.tradedOrdersOpen[tempKey] = tempKey
            # ------------------------------------------------------------------
        elif (vtOrderID in self.vtOrderIDListClose and tempKey in self.tradingOrdersClose.keys()):
            # ------------------------------------------------------------------
            self.tradingOrdersClose[tempKey]['volume'] -= self.stratTrade['volume']
            if self.tradingOrdersClose[tempKey]['volume'] == 0:
                self.tradingOrdersClose.pop(tempKey, None)
                self.tradedOrdersClose[tempKey] = tempKey
            # ------------------------------------------------------------------
        elif (vtOrderID in self.vtOrderIDListFailedInfo and tempKey in self.tradingOrdersFailedInfo.keys()):
            # ------------------------------------------------------------------
            self.tradingOrdersFailedInfo[tempKey]['volume'] -= self.stratTrade['volume']
            if self.tradingOrdersFailedInfo[tempKey]['volume'] == 0:
                self.tradingOrdersFailedInfo.pop(tempKey, None)
            # ------------------------------------------------------------------
            ## 需要更新一下 failedInfo
            self.stratTrade['TradingDay'] = self.ctaEngine.lastTradingDate
            self.processTradingOrdersFailedInfo(self.stratTrade)
        elif (vtOrderID in self.vtOrderIDListUpperLowerCum and tempKey in self.tradingOrdersUpperLowerCum.keys()):
            # ------------------------------------------------------------------
            self.tradingOrdersUpperLowerCum[tempKey]['volume'] -= self.stratTrade['volume']
            # ------------------------------------------------------------------
            if self.tradingOrdersUpperLowerCum[tempKey]['volume'] == 0:
                self.tradingOrdersUpperLowerCum.pop(tempKey, None)
                self.tradedOrdersUpperLowerCum[tempKey] = tempKey
        # elif (vtOrderID in self.vtOrderIDListWinner and tempKey in self.tradingOrdersWinner.keys()):
        #     # ------------------------------------------------------------------
        #     self.tradingOrdersWinner[tempKey]['volume'] -= self.stratTrade['volume']
        #     # ------------------------------------------------------------------
        #     if self.tradingOrdersWinner[tempKey]['volume'] == 0:
        #         self.tradingOrdersWinner.pop(tempKey, None)
        #         self.tradedOrdersWinner[tempKey] = tempKey

        ## =====================================================================
        ## 2. 更新 positionInfo
        ## =====================================================================
        if self.stratTrade['offset'] == u'开仓':
            ## ------------------------------------
            ## 处理开仓的交易订单            
            self.processOffsetOpen(self.stratTrade)
            ## ------------------------------------

            ## =================================================================
            ## william
            ## 如果有开仓的情况，则相应的发出平仓的订单，
            ## 成交价格为　UpperLimit / LowerLimit 的 (?)
            if self.tradingStart:
                ## -------------------------------------------------------------
                ## 1. 「开多」 --> sell@upper
                ## 2. 「开空」 --> cover@lower
                if self.stratTrade['direction'] == 'long':
                    tempDirection = 'sell'
                    tempPriceType = 'upper'
                elif self.stratTrade['direction'] == 'short':
                    tempDirection = 'cover'
                    tempPriceType = 'lower'
                ## -------------------------------------------------------------
                tempKey = (vtSymbol + '-' + tempDirection).encode('ascii','ignore')
                ## -------------------------------------------------------------
                
                if self.accountID not in self.WINNER_STRATEGY:
                    ## =============================================================
                    ## 涨跌停平仓单
                    ## 目前暂时不使用这个功能了
                    ## 不过不要删除，以后有可能会继续使用这个函数
                    ## -------------------------------------------------------------
                    if datetime.now().hour in [9,21] and datetime.now().minute < 2:
                        ## 成交之后先累计，待时间满足之后再一起下涨跌停平仓单
                        ## ---------------------------------------------------------
                        if tempKey in self.tradingOrdersUpperLowerCum.keys():
                            self.tradingOrdersUpperLowerCum[tempKey]['volume'] += self.stratTrade['volume']
                        else:
                            ## -----------------------------------------------------
                            ## 生成 tradingOrdersUpperLowerCum
                            self.tradingOrdersUpperLowerCum[tempKey] = {
                                    'vtSymbol'      : vtSymbol,
                                    'direction'     : tempDirection,
                                    'volume'        : self.stratTrade['volume'],
                                    'TradingDay'    : self.stratTrade['TradingDay'],
                                    'vtOrderIDList' : []
                                    }
                            ## -----------------------------------------------------
                        ## ---------------------------------------------------------
                    else:
                        ## 成交之后立即反手以涨跌停价格下平仓单
                        ## ---------------------------------------------------------
                        ## 生成 tradingOrdersUpperLower
                        self.tradingOrdersUpperLower[tempKey] = {
                                'vtSymbol'      : vtSymbol,
                                'direction'     : tempDirection,
                                'volume'        : self.stratTrade['volume'],
                                'TradingDay'    : self.stratTrade['TradingDay'],
                                'vtOrderIDList' : []
                                }
                        ## -------------------------------------------------------------

                        ## -------------------------------------------------------------
                        self.prepareTradingOrder(vtSymbol      = vtSymbol, 
                                                 tradingOrders = self.tradingOrdersUpperLower, 
                                                 orderIDList   = self.vtOrderIDListUpperLower,
                                                 priceType     = tempPriceType,
                                                 addTick       = 0)
                        # --------------------------------------------------------------
                        # 获得 vtOrderID
                        tempFields = ['TradingDay','vtSymbol','vtOrderIDList','direction','volume']
                        self.tradingOrdersUpperLower[tempKey]['vtOrderIDList'] = ujson.dumps(self.tradingOrdersUpperLower[tempKey]['vtOrderIDList'])
                        tempRes = pd.DataFrame([[self.tradingOrdersUpperLower[tempKey][k] for k in tempFields]], 
                                                columns = tempFields)
                        tempRes.insert(1,'strategyID', self.strategyID)
                        tempRes.rename(columns={'vtSymbol':'InstrumentID'}, inplace = True)
                        ## -------------------------------------------------------------
                        
                        ## -------------------------------------------------------------
                        try:
                            self.saveMySQL(df = tempRes, tbl = 'UpperLowerInfo', over = 'append')
                        except:
                            self.writeCtaLog(u'UpperLower 涨跌停平仓订单 写入 MySQL 数据库出错',
                                             logLevel = ERROR)
                        ## ---------------------------------------------------------
                        ## =============================================================

                elif self.accountID in self.WINNER_STRATEGY:
                    ## =============================================================
                    ## 止盈平仓单
                    ## -------------------------------------------------------------
                    if tempKey in self.tradingOrdersWinner.keys():
                        self.tradingOrdersWinner[tempKey]['volume'] += self.stratTrade['volume']
                    else:
                        ## ---------------------------------------------------------
                        ## 生成 tradingOrdersWinner
                        self.tradingOrdersWinner[tempKey] = {
                                'vtSymbol'      : vtSymbol,
                                'direction'     : tempDirection,
                                'volume'        : self.stratTrade['volume'],
                                'TradingDay'    : self.stratTrade['TradingDay'],
                                'vtOrderIDList' : []
                        }
                        ## ---------------------------------------------------------
                    ## =============================================================
            ## =================================================================

        elif self.stratTrade['offset'] in [u'平仓', u'平昨', u'平今']:
            ## -----------------------------------------------------------------
            ## 平仓只有在以下两个情况才处理
            ## 因为 failedInfo 已经预先处理过了
            if vtOrderID in list(set(self.vtOrderIDListClose) |
                               set(self.vtOrderIDListUpperLower) |
                               set(self.vtOrderIDListUpperLowerCum) |
                               set(self.vtOrderIDListUpperLowerTempCum) |
                               set(self.vtOrderIDListWinner) |
                               set(self.vtOrderIDListTempWinner)):
                self.processOffsetClose(self.stratTrade)
            ## -----------------------------------------------------------------

        ## ---------------------------------------------------------------------
        tempTradingInfo = pd.DataFrame([[self.stratTrade[k] for k in self.tradingInfoFields]], 
            columns = self.tradingInfoFields)
        self.updateTradingInfo(df = tempTradingInfo)
        # self.tradingInfo = self.tradingInfo.append(tempTradingInfo, ignore_index=True)
        ## ---------------------------------------------------------------------

        ########################################################################
        ## 处理 MySQL 数据库的 tradingOrders
        ## 如果成交了，需要从这里面再删除交易订单
        ########################################################################
        if vtOrderID in self.vtOrderIDListOpen + self.vtOrderIDListClose:
            self.updateTradingOrdersTable(self.stratTrade)
        ########################################################################

        ## =====================================================================
        # 发出状态更新事件
        self.tickTimer[vtSymbol] = datetime.now()
        self.putEvent()
        ## =====================================================================


    ############################################################################
    ## william
    ## 更新状态，需要订阅
    ############################################################################
    def processTradingStatus(self, event):
        """处理交易状态变更"""
        ## -----------------------
        if not self.trading:
            return
        ## -----------------------

        ## -----------------------
        cdef:
            int h = datetime.now().hour
            int m = datetime.now().minute
            int s = datetime.now().second
        if (s % 5 != 0):
            return
        ## -----------------------

        ## =====================================================================
        # self.CTPConnect = ujson.load(file(self.CTPConnectPath))[globalSetting.accountID]
        # if not self.CTPConnect['status'][self.className]:
        #     self.ctaEngine.stopStrategy(self.name)
        #     self.writeCtaLog(u'%s策略已停止' %self.name)
        #     return
        ## =====================================================================


        ## -----------------------
        self.updateTradingStatus()
        ## -----------------------

        if (h == self.tradingCloseHour and 
            m in [self.tradingCloseMinute1, (self.tradingCloseMinute2)] and 
            20 <= s <= 30 and (s % 5 == 0 or len(self.tradingOrdersClose) == 0)):
            ## =================================================================
            if self.ctaEngine.mainEngine.multiStrategy:
                self.tradingOrdersClose = self.fetchTradingOrders(stage = 'close')
                self.updateTradingOrdersVtOrderID(tradingOrders = self.tradingOrdersClose,
                                                  stage = 'close')
                self.updateVtOrderIDList('close')
                if len(self.tradingOrdersClose):
                    for k in self.tradingOrdersClose.keys():
                        self.tradingOrdersClose[k]['lastTimer'] -= timedelta(seconds = 60)
            ## =================================================================


        ## =====================================================================
        ## 更新 workingInfo
        ## =====================================================================
        if (m % 5 == 0 and 10 <= s <= 30 and s % 10 == 0):
            self.updateOrderInfo()
            ## ---------------------------------------
            if self.accountID in self.WINNER_STRATEGY:
                self.updateLastTickInfo()
            ## ---------------------------------------
            
            if self.tradingStart:
                self.updateWorkingInfo(self.tradingOrdersOpen, 'open')
                self.updateWorkingInfo(self.tradingOrdersClose, 'close')
                ## UpperLowerCum
                self.updateWorkingInfo(self.tradingOrdersUpperLowerCum, 'ul')

                if self.accountID in self.WINNER_STRATEGY:
                    ## Winner/Loser
                    self.updateWorkingInfo(self.tradingOrdersWinner, 'winner')

            if (h == 15 and self.trading):
                self.updateFailedInfo(
                    tradingOrders = self.tradingOrdersClose, 
                    tradedOrders  = self.tradedOrdersClose)
            ## -----------------------------------------------------------------
            ## 同步数据
            # if self.ip == '172.16.166.234':
            #     return

            # for tbl in ['positionInfo','tradingInfo','UpperLowerInfo','workingInfo']:
            #     if tbl in ['tradingInfo']:
            #         condition = "--where='TradingDay = {}'".format(self.tradingDay)
            #     else:
            #         condition = ""
            #     vtFunction.dbMySQLSync(
            #         # fromHost = '192.168.1.135', 
            #         fromHost = globalSetting().vtSetting['mysqlHost'],
            #         toHost = '47.98.117.71', 
            #         fromDB = self.ctaEngine.mainEngine.dataBase, 
            #         toDB = self.ctaEngine.mainEngine.dataBase,
            #         tableName = tbl,
            #         condition = condition)
            ## -----------------------------------------------------------------

    ## =========================================================================
    ## william
    ## 时间引擎
    ## =========================================================================
    def registerEvent(self):
        """注册事件监听"""
        ## ---------------------------------------------------------------------
        self.ctaEngine.eventEngine.register(EVENT_TIMER, self.processTradingStatus)
        ## ---------------------------------------------------------------------
