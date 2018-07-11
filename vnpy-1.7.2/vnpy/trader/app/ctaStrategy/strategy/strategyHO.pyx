# encoding: UTF-8

"""
HOStrategy 策略的交易实现
＠william
"""
from __future__ import division
import os,sys,subprocess

from vnpy.trader.vtConstant import EMPTY_STRING
from vnpy.trader.app.ctaStrategy.ctaTemplate import CtaTemplate
from vnpy.trader.vtEvent import *
from vnpy.trader import vtFunction
## -----------------------------------------------------------------------------
from logging import INFO, ERROR
from pandas import DataFrame
from pandas.io import sql

from datetime import datetime,time,timedelta
from pprint import pprint,pformat
from copy import copy
import math,random
import re,ast,json
## -----------------------------------------------------------------------------
from vnpy.trader.vtGlobal import globalSetting

########################################################################
class HOStrategy(CtaTemplate):
    """ HoldOn 持仓周期交易策略 """
    ############################################################################
    ## william
    ## 
    ## 策略类的名称和作者
    ## -------------------------------------------------------------------------
    name = u'HoldOn'
    strategyID = className = u'HOStrategy'
    author = 'Lin HuanGeng'
    ############################################################################

    #----------------------------------------------------------------------
    def __init__(self, ctaEngine, setting):
        """Constructor"""
        ## 从　ctaEngine 继承所有属性和方法
        super(HOStrategy, self).__init__(ctaEngine, setting)

        ## =====================================================================
        ## 交易时点
        self.tradingStartCounter = 0
        self.tradingOpenHour    = [21,9]
        self.tradingOpenMinute1 = 0
        self.tradingOpenMinute2 = 10

        self.tradingCloseHour    = 14
        self.tradingCloseMinute1 = 50
        self.tradingCloseMinute2 = 59
        ## =====================================================================

        ## ===================================================================== 
        ## william
        # 注意策略类中的可变对象属性（通常是list和dict等），在策略初始化时需要重新创建，
        # 否则会出现多个策略实例之间数据共享的情况，有可能导致潜在的策略逻辑错误风险，
        # 策略类中的这些可变对象属性可以选择不写，全都放在__init__下面，写主要是为了阅读
        # 策略时方便（更多是个编程习惯的选择） 
        # 
        ## ===================================================================== 

        ########################################################################
        ## william
        # 注册事件监听
        self.registerEvent()
        ########################################################################

    #----------------------------------------------------------------------
    def onInit(self):
        """初始化策略（必须由用户继承实现）"""
        self.writeCtaLog(u'%s策略初始化' %self.name)

        ## =====================================================================
        self.tradingOrdersOpen = self.fetchTradingOrders(stage = 'open')
        self.updateTradingOrdersVtOrderID(tradingOrders = self.tradingOrdersOpen,
                                          stage = 'open')
        self.updateVtOrderIDList('open')

        if len(self.tradingOrdersOpen):
            for k in self.tradingOrdersOpen.keys():
                self.tradingOrdersOpen[k]['lastTimer'] -= timedelta(seconds = 60)

        ## -----------------------------------------------------------------
        self.tradingOrdersClose = self.fetchTradingOrders(stage = 'close')
        self.updateTradingOrdersVtOrderID(tradingOrders = self.tradingOrdersClose,
                                          stage = 'close')
        self.updateVtOrderIDList('close')

        if len(self.tradingOrdersClose):
            for k in self.tradingOrdersClose.keys():
                self.tradingOrdersClose[k]['lastTimer'] -= timedelta(seconds = 60)
        ## =====================================================================

        ## =====================================================================
        if self.tradingOrdersFailedInfo:
            self.writeCtaLog("昨日失败需要执行的订单\n%s\n%s\n%s" 
                %('-'*80,
                  pformat(self.tradingOrdersFailedInfo),
                  '-'*80))
        if self.tradingOrdersOpen:
            self.writeCtaLog("当日需要执行的开仓订单\n%s\n%s\n%s" 
                %('-'*80,
                  pformat(self.tradingOrdersOpen),
                  '-'*80))
        if self.tradingOrdersClose:
            self.writeCtaLog("当日需要执行的平仓订单\n%s\n%s\n%s" 
                %('-'*80,
                  pformat(self.tradingOrdersClose),
                  '-'*80))
        ## =====================================================================

        ## =====================================================================
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

    #----------------------------------------------------------------------
    def onTick(self, tick):
        """收到行情TICK推送（必须由用户继承实现）"""

        ## =====================================================================
        if not self.trading:
            return 
        elif tick.datetime <= (datetime.now() - timedelta(seconds=10)):
            return
        ## 控制下单速度
        elif ((datetime.now() - self.tickTimer[tick.vtSymbol]).seconds < 1):
            return
        # =====================================================================

        cdef:
            char *id = tick.vtSymbol
            str tempPriceType

        ## =====================================================================
        ## 开仓信号
        if self.tradingStart:
            ## -----------------------------------------------------------------
            if (id in [self.tradingOrdersOpen[k]['vtSymbol'] 
                       for k in self.tradingOrdersOpen.keys()]):
                ## -------------------------------------------------------------
                if self.tradingSplit:            
                    tempOrderIDList = self.vtOrderIDListOpenSplit
                else:
                    tempOrderIDList = self.vtOrderIDListOpen

                self.prepareSplit(
                    vtSymbol = id,
                    tradingOrders = self.tradingOrdersOpen,
                    orderIDList = tempOrderIDList)
                ## -------------------------------------------------------------
            if (id in [self.tradingOrdersClose[k]['vtSymbol'] 
                       for k in self.tradingOrdersClose.keys()]):
                ## -------------------------------------------------------------
                tempDirection = [self.tradingOrdersClose[k]['direction']
                                    for k in self.tradingOrdersClose.keys()
                                    if self.tradingOrdersClose[k]['vtSymbol'] == id][0]

                tempPriceType = 'upper' if tempDirection == 'sell' else 'lower'
                ## -------------------------------------------------------------

                self.prepareTradingOrder(
                    vtSymbol      = id, 
                    tradingOrders = self.tradingOrdersClose, 
                    orderIDList   = self.vtOrderIDListUpperLower,
                    priceType     = tempPriceType)
                ## -------------------------------------------------------------
        ## =====================================================================

        ## =====================================================================
        ## 当天尾盘的平仓信号
        elif ((self.tradingBetween or self.tradingEnd) and
              id in [self.tradingOrdersClose[k]['vtSymbol'] 
                     for k in self.tradingOrdersClose.keys()]):
            ## ----------------------------
            if (self.initialCapital <= 0.5e7 and
                id[0:2] not in ['bu','cs','pb','c1','a1','b1',
                                'v1','y1','l1','p1','i1',
                                'FG','RM','OI','SM','SR','SF',
                                'TA','CY','CF'] and 
                datetime.now().minute < self.tradingCloseMinute2-5):
                tempPriceType = 'best'
            else:
                tempPriceType = 'last'
            ## ----------------------------

            self.prepareSplit(
                vtSymbol      = id,
                tradingOrders = self.tradingOrdersClose,
                orderIDList   = self.vtOrderIDListClose,
                priceType     = tempPriceType)
        ## =====================================================================


        ## =====================================================================
        ## william
        ## ---------------------------------------------------------------------
        if self.tradingOrdersFailedInfo and self.tradingStart:
            self.prepareTradingOrder(
                vtSymbol      = id, 
                tradingOrders = self.tradingOrdersFailedInfo, 
                orderIDList   = self.vtOrderIDListFailedInfo,
                priceType     = 'chasing',
                addTick       = +1)
        ## =====================================================================


    #+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    def onOrder(self, order):
        """收到委托变化推送（必须由用户继承实现）"""
        pass

    #----------------------------------------------------------------------
    def onTrade(self, trade):
        """处理成交订单"""
        cdef:
            char *vtSymbol = trade.vtSymbol
            char *vtOrderID = trade.vtOrderID
            str tempKey, tempDirection

        ## =====================================================================
        ## 0. 数据预处理
        ## =====================================================================
        self.stratTrade = copy(trade.__dict__)
        self.stratTrade['InstrumentID'] = vtSymbol
        self.stratTrade['strategyID'] = self.strategyID
        self.stratTrade['tradeTime'] = datetime.now().strftime('%Y-%m-%d') + " " + self.stratTrade['tradeTime']
        self.stratTrade['TradingDay'] = self.tradingDate

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
            if self.tradingOrdersOpen[tempKey]['volume'] <= 0:
                self.tradingOrdersOpen.pop(tempKey, None)
                self.tradedOrdersOpen[tempKey] = tempKey
            # ------------------------------------------------------------------
        elif (vtOrderID in self.vtOrderIDListClose + self.vtOrderIDListUpperLower and 
              tempKey in self.tradingOrdersClose.keys()):
            # ------------------------------------------------------------------
            self.tradingOrdersClose[tempKey]['volume'] -= self.stratTrade['volume']
            if self.tradingOrdersClose[tempKey]['volume'] <= 0:
                self.tradingOrdersClose.pop(tempKey, None)
                self.tradedOrdersClose[tempKey] = tempKey
            # ------------------------------------------------------------------
        elif (vtOrderID in self.vtOrderIDListFailedInfo and 
              tempKey in self.tradingOrdersFailedInfo.keys()):
            # ------------------------------------------------------------------
            self.tradingOrdersFailedInfo[tempKey]['volume'] -= self.stratTrade['volume']
            if self.tradingOrdersFailedInfo[tempKey]['volume'] <= 0:
                self.tradingOrdersFailedInfo.pop(tempKey, None)
            # ------------------------------------------------------------------
            ## 需要更新一下 failedInfo
            self.stratTrade['TradingDay'] = self.ctaEngine.lastTradingDate
            self.processTradingOrdersFailedInfo(self.stratTrade)

        ## =====================================================================
        ## 2. 更新 positionInfo
        ## =====================================================================
        if self.stratTrade['offset'] == u'开仓':
            ## ------------------------------------
            ## 处理开仓的交易订单            
            self.processOffsetOpen(self.stratTrade)
            ## ------------------------------------
        elif (self.stratTrade['offset'] in [u'平仓', u'平昨', u'平今'] and 
             vtOrderID in self.vtOrderIDListClose):
            ## -----------------------------------------------------------------
            ## 平仓只有在以下两个情况才处理
            ## 因为 failedInfo 已经预先处理过了
            self.processOffsetClose(self.stratTrade)
            ## -----------------------------------------------------------------

        ## ---------------------------------------------------------------------
        tempTradingInfo = DataFrame(
            [[self.stratTrade[k] for k in self.tradingInfoFields]], 
            columns = self.tradingInfoFields)
        self.updateTradingInfo(df = tempTradingInfo)
        # self.tradingInfo = self.tradingInfo.append(tempTradingInfo, ignore_index=True)
        ## ---------------------------------------------------------------------

        ########################################################################
        ## 处理 MySQL 数据库的 tradingOrders
        ## 如果成交了，需要从这里面再删除交易订单
        ########################################################################
        if (vtOrderID in self.vtOrderIDListOpen + 
                         self.vtOrderIDListOpenSplit + 
                         self.vtOrderIDListClose +
                         self.vtOrderIDListUpperLower):
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
        n = datetime.now()
        ## -----------------------
        cdef:
            int h = n.hour
            int m = n.minute
            int s = n.second
        if (s % 5 != 0):
            return
        ## -----------------------

        ## -----------------------
        self.updateTradingStatus()
        ## -----------------------

        ## =====================================================================
        if (h == self.tradingCloseHour and 
            m in [self.tradingCloseMinute1, (self.tradingCloseMinute2)] and 
            20 <= s <= 30 and (s % 5 == 0 or len(self.tradingOrdersClose) == 0)):
            ## -----------------------------------------------------------------
            self.tradingOrdersClose = self.fetchTradingOrders(stage = 'close')
            self.updateTradingOrdersVtOrderID(
                tradingOrders = self.tradingOrdersClose,
                stage = 'close')
            self.updateVtOrderIDList('close')
            if len(self.tradingOrdersClose):
                for k in self.tradingOrdersClose.keys():
                    self.tradingOrdersClose[k]['lastTimer'] -= timedelta(seconds = 60)
        ## =====================================================================


        ## =====================================================================
        ## 更新 workingInfo
        ## =====================================================================
        if (m % 5 == 0 and 10 <= s <= 30 and s % 10 == 0):
            self.updateOrderInfo()
            if self.tradingStart:
                self.updateWorkingInfo(self.tradingOrdersOpen, 'open')
                self.updateWorkingInfo(self.tradingOrdersClose, 'close')
            if (h == 15 and self.trading):
                ## -----------------------------------------
                self.updateFailedInfo(
                    tradingOrders = self.tradingOrdersOpen, 
                    tradedOrders  = self.tradedOrdersOpen)
                ## -----------------------------------------

                ## -----------------------------------------
                self.updateFailedInfo(
                    tradingOrders = self.tradingOrdersClose, 
                    tradedOrders  = self.tradedOrdersClose)
                ## -----------------------------------------


    ## =========================================================================
    ## william
    ## 时间引擎
    ## =========================================================================
    def registerEvent(self):
        """注册事件监听"""
        ## ---------------------------------------------------------------------
        self.ctaEngine.eventEngine.register(EVENT_TIMER, self.processTradingStatus)
        ## ---------------------------------------------------------------------
