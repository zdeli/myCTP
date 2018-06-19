# encoding: UTF-8

'''
hello
本文件包含了CTA引擎中的策略开发用模板，开发策略时需要继承CtaTemplate类。
'''

from __future__ import division
import os,sys,subprocess

from vnpy.trader.vtConstant import *
from vnpy.trader.vtObject import VtBarData
from vnpy.trader.vtEvent import *

from .ctaBase import *
from vnpy.trader import vtFunction

## -----------------------------------------------------------------------------
from logging import INFO, ERROR
import talib
import pandas as pd
from pandas.io import sql
from datetime import datetime,time,timedelta
import time
import math,random

import re,ast
import ujson
from copy import copy

## -----------------------------------------------------------------------------
reload(sys) # Python2.5 初始化后会删除 sys.setdefaultencoding 这个方法，我们需要重新载入   
sys.setdefaultencoding('utf-8')   
from vnpy.trader.vtGlobal import globalSetting

########################################################################
class CtaTemplate(object):
    """CTA策略模板"""
    
    ## -------------------------------------------------------------------------
    # 策略类的名称和作者
    name       = ""              # 策略实例名称
    className  = 'CtaTemplate'
    strategyID = ""              # william:暂时与 className 一样
    author     = ""
    
    # 策略的基本参数
    vtSymbol = EMPTY_STRING        # 交易的合约vt系统代码    
    productClass = EMPTY_STRING    # 产品类型（只有IB接口需要）
    currency = EMPTY_STRING        # 货币（只有IB接口需要）
    ## 本地 IP 地址
    ip = vtFunction.getHostIP()
    ## -------------------------------------------------------------------------
    
    ## -------------------------------------------------------------------------
    ## 各种控制条件
    ## 策略的基本变量，由引擎管理
    inited         = False                    # 是否进行了初始化
    trading        = False                    # 是否启动交易，由引擎管理
    tradingStart   = False                    # 开盘启动交易
    tradingEnd     = False                    # 收盘开启交易
    pos            = 0                        # 持仓情况
    sendMailStatus = False                    # 是否已经发送邮件
    tradingClosePositionAll    = False        # 是否强制平仓所有合约
    tradingClosePositionSymbol = False        # 是否强制平仓单个合约
    ## -------------------------------------------------------------------------
    
    # 参数列表，保存了参数的名称
    paramList = ['name',
                 'className',
                 'author',
                 'vtSymbol']
    
    # 变量列表，保存了变量的名称
    varList = ['inited',
               'trading',
               'pos']

    ## =========================================================================
    # 同步列表，保存了需要保存到数据库的变量名称
    syncList = ['pos']
    ## =========================================================================

    ## -------------------------------------------------------------------------
    tickTimer    = {}                  # 计时器, 用于记录单个合约发单的间隔时间
    vtSymbolList = []                  # 策略的所有合约存放在这里
    ## -------------------------------------------------------------------------

    ## -------------------------------------------------------------------------
    ## 各种交易订单的合成
    ## 交易订单存放位置
    ## 字典格式如下
    ## 1. vtSymbol
    ## 2. direction: buy, sell, short, cover
    ## 3. volume
    ## 4. TradingDay
    ## 5. vtOrderID
    ## -------------------------------------------------------------------------

    ## -------------------------------------------------------------------------
    tradedOrders           = {}        # 当日订单完成的情况
    tradedOrdersOpen       = {}        # 当日开盘完成的已订单
    tradedOrdersClose      = {}        # 当日收盘完成的已订单
    tradedOrdersFailedInfo = {}        # 昨天未成交订单的已交易订单
    ## -------------------------------------------------------------------------

    ## -------------------------------------------------------------------------
    tradingOrdersClosePositionAll    = {}     ## 一键全平仓的交易订单
    tradingOrdersClosePositionSymbol = {}     ## 一键平仓合约的交易订单

    ## -------------------------------------------------------------------------
    ## 各种交易订单的合成
    ## -------------------------------------------------------------------------
    vtOrderIDList           = []        # 保存委托代码的列表
    vtOrderIDListOpen       = []        # 开盘的订单
    vtOrderIDListOpenSplit   = []       # 开盘的拆单
    vtOrderIDListClose      = []        # 收盘的订单
    vtOrderIDListFailedInfo = []        # 失败的合约订单存储
    vtOrderIDListUpperLower = []        # 涨跌停价格成交的订单
    vtOrderIDListUpperLowerCum = []    # 涨跌停价格成交的订单
    vtOrderIDListUpperLowerTempCum = []    # 涨跌停价格成交的订单
    vtOrderIDListWinner     = []       # 止盈平仓单
    vtOrderIDListTempWinner = []       # 止盈平仓单
    vtOrderIDListAll        = []       # 所有订单集合
    ## -------------------------------------------------------------------------
    
    ## -------------------------------------------------------------------------
    vtOrderIDListClosePositionAll    = []     # 一键全平仓
    vtOrderIDListClosePositionSymbol = []     # 一键全平仓
    ## -------------------------------------------------------------------------
    vtOrderIDListAll   = []                   # 所有订单集合

    ## 子订单的拆单比例实现
    subOrdersLevel = {'level0':{'weight': 0.30, 'deltaTick': 0},
                      'level1':{'weight': 0.70, 'deltaTick': 1},
                      'level2':{'weight': 0, 'deltaTick': 2}
                     }
    totalOrderLevel = 1 + (len(subOrdersLevel) - 1) * 2

    ## -------------------------------------------------------------------------
    ## 保存交易记录: tradingInfo
    ## 保存订单记录: orderInfo
    ## -------------------------------------------------------------------------
    tradingInfoFields = ['strategyID','InstrumentID','TradingDay','tradeTime',
                         'direction','offset','volume','price']
    orderInfoFields   = ['strategyID', 'vtOrderID', 'symbol', 'orderTime',
                         'status', 'direction', 'cancelTime', 'tradedVolume',
                         'frontID', 'sessionID', 'offset', 'price', 'totalVolume']
    failedInfoFields  = ['strategyID','InstrumentID','TradingDay',
                         'direction','offset','volume']

    barHeader = ['date','time','symbol','exchange',
                 'open','high','low','close',
                 'volume','turnover']    

    ## --------------------------------------------------------------------------
    def __init__(self, ctaEngine, setting):
        """Constructor"""
        ## 通过 ctaEngine 调用 mainEngine
        self.ctaEngine = ctaEngine

        ## =====================================================================
        ## 配置文件
        ## -------
        self.CTPConnectFile = 'CTP_connect.json'
        path = os.path.normpath(
            os.path.join(
                os.path.dirname(__file__),
                '..', '..', '..', '..')
            )
        self.CTPConnectPath = os.path.join(path, 'trading', 'account', self.CTPConnectFile)
        self.CTPConnect = ujson.load(file(self.CTPConnectPath))[globalSetting.accountID]
        ## =====================================================================

        ## =====================================================================
        ## 交易时点
        self.tradingDay          = self.ctaEngine.tradingDay
        self.lastTradingDay      = self.ctaEngine.lastTradingDay

        self.tradingStartCounter = 0
        self.tradingOpenHour    = [21,9]
        self.tradingOpenMinute1 = 0
        self.tradingOpenMinute2 = 10

        self.tradingCloseHour    = 14
        self.tradingCloseMinute1 = 50
        self.tradingCloseMinute2 = 59

        self.accountID           = globalSetting.accountID
        self.randomNo            = 50 + random.randint(-5,5)    ## 随机间隔多少秒再下单
        ## =====================================================================

        ## =====================================================================
        ## 把　MySQL 数据库的　TradingDay　调整为　datetime 格式
        conn = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
        cursor = conn.cursor()
        cursor.execute("""
                        ALTER TABLE failedInfo
                        MODIFY TradingDay date not null;
                       """)
        cursor.execute("""
                        ALTER TABLE positionInfo
                        MODIFY TradingDay date not null;
                       """)
        try:
            cursor.execute("""ALTER TABLE positionInfo DROP primary key""")
        except:
            pass
        cursor.execute("""
                        ALTER TABLE positionInfo 
                        ADD PRIMARY key (strategyID,InstrumentID,TradingDay,direction);
                       """)
        conn.commit()
        conn.close()        
        ## =====================================================================

        ## =====================================================================
        # 设置策略的参数
        if setting:
            d = self.__dict__
            for key in self.paramList:
                if key in setting:
                    d[key] = setting[key]
        ## =====================================================================

    #----------------------------------------------------------------------
    def onInit(self):
        """初始化策略（必须由用户继承实现）"""
        raise NotImplementedError
        

    def onStart(self):
        """启动策略（必须由用户继承实现）"""
        ## =====================================================================
        ## 策略启动
        ## =====================================================================
        self.ctaEngine.mainEngine.writeLog('-'*48, gatewayName = '')
        self.writeCtaLog(u'%s策略启动' %self.name)
        self.ctaEngine.mainEngine.writeLog('-'*48, gatewayName = '')
        self.trading = True
        self.putEvent()
        

    #+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    def onStop(self):
        """停止策略（必须由用户继承实现）"""
        ## =====================================================================
        ## 策略停止
        ## =====================================================================
        self.writeCtaLog(u'%s策略停止' %self.name)
        self.trading = False
        ## ---------------------------------------------------------------------
        ## 取消所有的订单
        self.vtOrderIDListAll = list(set(self.vtOrderIDList) | 
                                     set(self.vtOrderIDListOpen) |
                                     set(self.vtOrderIDListClose) |
                                     set(self.vtOrderIDListFailedInfo) |
                                     set(self.vtOrderIDListClosePositionAll) |
                                     set(self.vtOrderIDListClosePositionSymbol))
        ## ---------------------------------------------------------------------
        if len(self.vtOrderIDListAll) != 0:
            for vtOrderID in self.vtOrderIDListAll:
                self.cancelOrder(vtOrderID)
        ## ---------------------------------------------------------------------
        self.putEvent()

    #----------------------------------------------------------------------
    def onTick(self, tick):
        """收到行情TICK推送（必须由用户继承实现）"""
        raise NotImplementedError

    #----------------------------------------------------------------------
    def onOrder(self, order):
        """收到委托变化推送（必须由用户继承实现）"""
        raise NotImplementedError
    
    #----------------------------------------------------------------------
    def onTrade(self, trade):
        """收到成交推送（必须由用户继承实现）"""
        raise NotImplementedError

    #----------------------------------------------------------------------
    def onBar(self, bar):
        """收到Bar推送（必须由用户继承实现）"""
        raise NotImplementedError
    
    #----------------------------------------------------------------------
    def onStopOrder(self, so):
        """收到停止单推送（必须由用户继承实现）"""
        raise NotImplementedError
    
    #----------------------------------------------------------------------
    def buy(self, str vtSymbol, price, int volume, stop=False):
        """买开"""
        return self.sendOrder(vtSymbol, CTAORDER_BUY, price, volume, stop)
    
    #----------------------------------------------------------------------
    def sell(self, str vtSymbol, price, int volume, stop=False):
        """卖平"""
        return self.sendOrder(vtSymbol, CTAORDER_SELL, price, volume, stop)       

    #----------------------------------------------------------------------
    def short(self, str vtSymbol, price, int volume, stop=False):
        """卖开"""
        return self.sendOrder(vtSymbol, CTAORDER_SHORT, price, volume, stop)          
 
    #----------------------------------------------------------------------
    def cover(self, str vtSymbol, price, int volume, stop=False):
        """买平"""
        return self.sendOrder(vtSymbol, CTAORDER_COVER, price, volume, stop)
    
    ## =========================================================================
    ## william
    ## =========================================================================
    #----------------------------------------------------------------------
    def sendOrder(self, 
                  str vtSymbol, 
                  orderType, 
                  price, 
                  int volume, 
                  stop = False):
        """发送委托"""
        if self.trading:
            vtOrderIDList = self.ctaEngine.sendOrder(vtSymbol, orderType, price, volume, self) 
            return vtOrderIDList
        else:
            # 交易停止时发单返回空字符串
            # self.writeCtaLog(u'策略未启动')
            return [] 


    #----------------------------------------------------------------------
    def cancelOrder(self, str vtOrderID):
        """撤单"""
        # 如果发单号为空字符串，则不进行后续操作
        if not vtOrderID:
            return
        self.ctaEngine.cancelOrder(vtOrderID)
            
    #----------------------------------------------------------------------
    def cancelAll(self):
        """全部撤单"""
        self.ctaEngine.cancelAll(self.name)
        
    #----------------------------------------------------------------------
    def loadTick(self):
        """读取tick数据"""
        ## =====================================================================
        ## william
        pass
        ## =====================================================================

    #----------------------------------------------------------------------
    def loadBar(self):
        """读取bar数据"""
        ## =====================================================================
        ## william
        pass
        ## =====================================================================
    
    #----------------------------------------------------------------------
    def writeCtaLog(self, content, logLevel = INFO):
        """记录CTA日志"""
        content = u'策略' + self.name + ':' + content
        self.ctaEngine.writeCtaLog(content, logLevel = logLevel)
        
    #----------------------------------------------------------------------
    def putEvent(self):
        """发出策略状态变化事件"""
        self.ctaEngine.putStrategyEvent(self.name)
        
    #----------------------------------------------------------------------
    def getEngineType(self):
        """查询当前运行的环境"""
        return self.ctaEngine.engineType
    
    #----------------------------------------------------------------------
    def saveSyncData(self):
        """保存同步数据到数据库"""
        self.ctaEngine.saveSyncData(self)

    ## =========================================================================
    ## william
    ## 从 MySQL 数据库获取交易订单
    ## =========================================================================
    def fetchTradingOrders(self, str stage):
        """ 从 MySQL 数据库获取交易订单 """
        ## ---------------------------------------------------------------------
        ##@param stage: 1.'open', 2.'close'
        ##@param tradingOrdersX: 1,'tradingOrdersOpen', 2.'tradingOrdersClose'
        ## ---------------------------------------------------------------------
        tempOrders = vtFunction.dbMySQLQuery(self.ctaEngine.mainEngine.dataBase,
            """
            SELECT *
            FROM tradingOrders
            WHERE strategyID = '%s'
            AND TradingDay = '%s'
            AND stage = '%s'
            """ %(self.strategyID, self.ctaEngine.tradingDate, stage))

        cdef dict tradingOrdersX = {}
        ## ---------------------------------------------------------------------
        if len(tempOrders) == 0:
            return tradingOrdersX

        cdef:
            int volume_0, volume_1, volume_2
            int totalVolume
            str tempKey
            int i

        ## ---------------------------------------------------------------------
        for i in xrange(len(tempOrders)):
            id = tempOrders.at[i,'InstrumentID'].encode('ascii','ignore')
            tempKey = (id + '-' + tempOrders.at[i,'orderType']).encode('ascii','ignore')
            ##
            tradingOrdersX[tempKey] = {
                'vtSymbol'      : id,
                'direction'     : tempOrders.at[i,'orderType'].encode('ascii','ignore'),
                'volume'        : tempOrders.at[i,'volume'],
                'TradingDay'    : tempOrders.at[i,'TradingDay'],
                'vtOrderIDList' : [],
                'subOrders'     : {},
                'lastTimer'     : datetime.now()
                }
            ## -----------------------------------------------------------------
            ## 开盘的拆单
            if stage == 'open':
                totalVolume = tempOrders.at[i,'volume']
                ## -------------------------------------------------------------
                if totalVolume < 3:
                    volume_2 = 0
                    volume_1 = 0
                    volume_0 = totalVolume
                elif 3 <= totalVolume < 5:
                    volume_2 = 0
                    volume_1 = 1
                    volume_0 = totalVolume - volume_1 * 2
                elif totalVolume >= 5:
                    volume_2 = totalVolume * self.subOrdersLevel['level2']['weight'] // 2
                    volume_1 = (totalVolume - volume_2*2) * self.subOrdersLevel['level1']['weight'] // 2
                    volume_0 = totalVolume - (volume_1 + volume_2) * 2
                ## --------------------------------------------------   -----------
                tradingOrdersX[tempKey]['subOrders'] = {'level0':{
                                                                 'volume': int(volume_0),
                                                                 'deltaTick': 0,
                                                                 'status': None},
                                                        'level1':{
                                                                 'volume': int(volume_1),
                                                                 'deltaTick': 1,
                                                                 'status_u': None,
                                                                 'status_d': None},
                                                        'level2':{
                                                                 'volume': int(volume_2),
                                                                 'deltaTick': 2,
                                                                 'status_u': None,
                                                                 'status_d': None}}
            ## -----------------------------------------------------------------
            # self.tickTimer[tempOrders.at[i,'InstrumentID']] = datetime.now()
            self.tickTimer[id] = datetime.now()
        ## ---------------------------------------------------------------------
        return tradingOrdersX


    ############################################################################
    ## william
    ## 处理前一日未成交的订单
    ############################################################################
    def processFailedInfo(self, failedInfo):
        """处理未成交订单"""
        ## =====================================================================
        if len(failedInfo) == 0:
            return
        ## =====================================================================

        self.tradingOrdersFailedInfo = {}

        cdef:
            str tempDirection
            int tempVolume

        ## =====================================================================
        for i in xrange(len(failedInfo)):
            ## -------------------------------------------------------------
            ## direction
            if failedInfo.loc[i,'direction'] == 'long':
                if failedInfo.loc[i,'offset'] == 'open':
                    tempDirection = 'buy'
                elif failedInfo.loc[i,'offset'] == 'close':
                    tempDirection = 'cover'
            elif failedInfo.loc[i,'direction'] == 'short':
                if failedInfo.loc[i,'offset'] == 'open':
                    tempDirection = 'short'
                elif failedInfo.loc[i,'offset'] == 'close':
                    tempDirection = 'sell'
            ## -------------------------------------------------------------
            ## volume
            tempVolume     = failedInfo.loc[i,'volume']
            tempKey        = failedInfo.loc[i,'InstrumentID'] + '-' + tempDirection
            tempTradingDay = failedInfo.loc[i,'TradingDay']
            
            self.tradingOrdersFailedInfo[tempKey] = {
                'vtSymbol'      : failedInfo.loc[i,'InstrumentID'],
                'direction'     : tempDirection,
                'volume'        : tempVolume,
                'TradingDay'    : tempTradingDay,
                'vtOrderIDList' : []
                }
        ## =====================================================================


    def updateTradingOrdersVtOrderID(self, dict tradingOrders, str stage):
        """
        更新交易订单的 vtOrderID
        """
        if len(tradingOrders) == 0:
            return
        ## =====================================================================
        ## MySQL 数据库保存的活跃订单
        mysqlWorkingInfo = vtFunction.dbMySQLQuery(self.ctaEngine.mainEngine.dataBase,
                            """
                            SELECT *
                            FROM workingInfo
                            WHERE strategyID = '%s'
                            AND TradingDay = %s
                            AND stage = '%s'
                            """ %(self.strategyID, self.ctaEngine.tradingDay, stage))
        ## 交易所保存的活跃订单
        cdef list exchWorkingInfo = [self.ctaEngine.mainEngine.getAllWorkingOrders()[j].vtOrderID 
                           for j in xrange(len(self.ctaEngine.mainEngine.getAllWorkingOrders()))]            
        ## =====================================================================
        
        cdef:
            str key
            char* vtOrderID
            list tempVtOrderIDList

        for key in tradingOrders.keys():
            temp = mysqlWorkingInfo.loc[(mysqlWorkingInfo.vtSymbol == tradingOrders[key]['vtSymbol']) & 
                                        (mysqlWorkingInfo.orderType == tradingOrders[key]['direction'])].reset_index(drop = True)
            if len(temp) == 0:
                continue
            tempVtOrderIDList = ast.literal_eval(temp.at[0,'vtOrderIDList'])

            if all(vtOrderID not in exchWorkingInfo for vtOrderID in tempVtOrderIDList):
                continue

            if (not tradingOrders[key]['vtOrderIDList']):
                tradingOrders[key]['vtOrderIDList'] = tempVtOrderIDList
            else:
                tradingOrders[key]['vtOrderIDList'] = list(
                    set(tradingOrders[key]['vtOrderIDList']) | 
                    set(tempVtOrderIDList))
            ## -----------------------------------------------------------------
            for vtOrderID in tempVtOrderIDList:
                self.ctaEngine.orderStrategyDict[vtOrderID] = self.ctaEngine.strategyDict[self.name]
        ## =====================================================================


    def updateVtOrderIDList(self, str stage):
        """
        更新 vtOrderIDList
        """
        ## =====================================================================
        ## MySQL 数据库保存的活跃订单
        mysqlWorkingInfo = vtFunction.dbMySQLQuery(self.ctaEngine.mainEngine.dataBase,
                            """
                            SELECT *
                            FROM workingInfo
                            WHERE strategyID = '%s'
                            AND TradingDay = %s
                            AND stage = '%s'
                            """ %(self.strategyID, self.ctaEngine.tradingDay, stage))
        if len(mysqlWorkingInfo) == 0:
            return

        cdef:
            list tempVtOrderIDList = []
            int i

        for i in xrange(len(mysqlWorkingInfo)):
            tempVtOrderIDList.extend(ast.literal_eval(mysqlWorkingInfo.at[i,'vtOrderIDList']))
        ## =====================================================================
        if stage == 'open':
            self.vtOrderIDListOpen = list(set(self.vtOrderIDListOpen) |
                                          set(tempVtOrderIDList))
        elif stage == 'close':
            self.vtOrderIDListClose = list(set(self.vtOrderIDListClose) |
                                           set(tempVtOrderIDList))

    ############################################################################
    ## william
    ## 限制价格在 UpperLimit 和 LowerLimit 之间
    ############################################################################
    def priceBetweenUpperLower(self, price, str vtSymbol):
        ## -----------------------------------------------------------
        cdef float tempPriceTick = self.ctaEngine.tickInfo[vtSymbol]['priceTick']
        ## -----------------------------------------------------------
        cdef float tempUpperLimit = self.ctaEngine.lastTickDict[vtSymbol]['upperLimit'] - tempPriceTick
        cdef float tempLowerLimit = self.ctaEngine.lastTickDict[vtSymbol]['lowerLimit'] + tempPriceTick
        return min(max(tempLowerLimit, price), tempUpperLimit)

    ############################################################################
    ## william
    ## 处理订单，并生成相应的字典格式
    ## @param vtSymbol: 合约代码
    ## @param orderDict: 订单的字典格式
    ## @param orderIDList: 订单列表
    ############################################################################
    def prepareTradingOrder(self, 
                            str vtSymbol, 
                            dict tradingOrders, 
                            list orderIDList, 
                            str priceType, 
                            price = None, 
                            int addTick = 0, 
                            float discount = 0.0):
        """处理订单"""

        ## ---------------------------------------------------------------------
        cdef:
            list tempTradingList
        ## ---------------------------------------------------------------------

        ## 生成交易列表
        tempTradingList = [k for k in tradingOrders.keys() 
                             if tradingOrders[k]['vtSymbol'] == vtSymbol and
                                tradingOrders[k]['volume'] != 0]
        ## ---------------------------------------------------------------------
        if not tempTradingList:
            return
        ## ---------------------------------------------------------------------
        allOrders = self.ctaEngine.mainEngine.getAllOrdersDataFrame()
        if len(allOrders):
            tempFinishedOrders = allOrders[(allOrders.vtSymbol == vtSymbol) & \
                                           (allOrders.status.isin([u'已撤销',u'全部成交'])) & \
                                           (allOrders.vtOrderID.isin(orderIDList))].vtOrderID.values
        else:
            tempFinishedOrders = []

        cdef:
            char* vtOrderID

        for i in tempTradingList:
            ## -------------------------------------------------------------
            ## 如果交易量依然是大于 0 ，则需要继续发送订单命令
            ## -------------------------------------------------------------
            if ((not tradingOrders[i]['vtOrderIDList']) or 
                (all(vtOrderID in tempFinishedOrders for 
                                  vtOrderID in tradingOrders[i]['vtOrderIDList']))):
                self.sendTradingOrder(tradingOrders = tradingOrders,
                                      orderDict     = tradingOrders[i],
                                      orderIDList   = orderIDList,
                                      priceType     = priceType,
                                      price         = price,
                                      addTick       = addTick,
                                      discount      = discount)
            if (self.tradingEnd and 
                ((datetime.now() - self.tickTimer[vtSymbol]).seconds > 3) and 
                len(tradingOrders[i]['vtOrderIDList'])):
                tempWorkingOrders = allOrders[(allOrders.status.isin([u'未成交',u'部分成交'])) &\
                                              (allOrders.vtSymbol == vtSymbol) &\
                                              (allOrders.vtOrderID.isin(orderIDList))].vtOrderID.values
                if not tempWorkingOrders:
                    return
                for vtOrderID in tradingOrders[i]['vtOrderIDList']:
                    if vtOrderID in tempWorkingOrders:
                        self.cancelOrder(vtOrderID)
                ## -------------------------------------------------------------
                self.tickTimer[vtSymbol] = datetime.now()

    ############################################################################
    ## william
    ## 实现拆分订单
    ############################################################################
    def prepareTradingOrderSplit(self, 
                                 str vtSymbol, 
                                 dict tradingOrders, 
                                 list orderIDList, 
                                 str priceType, 
                                 price = None, 
                                 int addTick = 0, 
                                 float discount = 0.0):
        """处理订单"""
        ## 生成交易列表
        ## ---------------------------------------------------------------------
        cdef:
            list tempTradingList
        ## ---------------------------------------------------------------------

        tempTradingList = [k for k in tradingOrders.keys() 
                             if tradingOrders[k]['vtSymbol'] == vtSymbol and
                                tradingOrders[k]['volume'] != 0]
        ## ---------------------------------------------------------------------
        if not tempTradingList:
            return

        cdef:
            int tempCanceledVolume
            int tempWorkingVolume, tempFinishedVolume
            int remainingVolume, totalVolume
            int deltaTick, deltaTick_quick, deltaTick_slow
            str status_quick, status_slow
            float remainingMinute
            str i, l
            int h = datetime.now().hour
            int m = datetime.now().minute
        ## ---------------------------------------------------------------------
        allOrders = self.ctaEngine.mainEngine.getAllOrdersDataFrame()
        if len(allOrders):
            tempWorkingOrders  = allOrders[(allOrders['vtSymbol'] == vtSymbol) & \
                                           (allOrders['status'].isin([u'未成交',u'部分成交'])) & \
                                           (allOrders['vtOrderID'].isin(orderIDList))]
            tempWorkingVolume = sum(tempWorkingOrders.totalVolume)
        else:
            tempWorkingVolume = 0

        for i in tempTradingList:
            ## -------------------------------------------------------------
            ## 如果交易量依然是大于 0 ，则需要继续发送订单命令
            ## -------------------------------------------------------------
            if self.tradingStart:
                ## =============================================================
                totalVolume = tradingOrders[i]['subOrders']['level0']['volume'] + \
                              sum([tradingOrders[i]['subOrders'][l]['volume'] for l in ['level1','level2']]) * 2
                ## ---------------------------------------------------------------------------------
                if len(allOrders):
                    tempCanceledOrder  = allOrders.loc[(allOrders.status.isin([u'已撤销'])) &\
                                                       (allOrders.vtSymbol == vtSymbol) &\
                                                       (allOrders.vtOrderID.isin(orderIDList))]
                    tempCanceledVolume = sum(tempCanceledOrder.totalVolume)
                    tempFinishedOrders = allOrders[(allOrders.status.isin([u'全部成交'])) &\
                                                   (allOrders.vtSymbol == vtSymbol) &\
                                                   (allOrders.vtOrderID.isin(orderIDList))]
                    tempFinishedVolume = sum(tempFinishedOrders.totalVolume)
                else:
                    tempCanceledOrder  = []
                    tempCanceledVolume = 0
                    tempFinishedVolume = 0
                ## 剩余待下单的手数
                remainingVolume = totalVolume - tempWorkingVolume - tempFinishedVolume
                ## 如果所有的订单已经在 working 的状态，
                ## 则不要再下单了
                if remainingVolume <= 0:
                    return
                ## ---------------------------------------------------------------------------------
                
                ## ---------------------------------------------------------------------------------
                if tradingOrders[i]['direction'] == 'buy':
                    price_0 = self.ctaEngine.lastTickDict[vtSymbol]['openPrice'] * (1 - discount)
                elif tradingOrders[i]['direction'] == 'short':
                    price_0 = self.ctaEngine.lastTickDict[vtSymbol]['openPrice'] * (1 + discount)
                ## ---------------------------------------------------------------------------------

                # ---------------------------------------------------------------------------------
                # -------------------------------
                # level0 是肯定都要发的
                # level0 优先下单
                # 如果是最高档次有限下单，
                # 这把这段代码放在　level2 level1 后面
                # 其他不用改动
                # --------------------------------
                if (not tradingOrders[i]['subOrders']['level0']['status']):
                    self.sendTradingOrder(tradingOrders = tradingOrders,
                                          orderDict     = tradingOrders[i],
                                          orderIDList   = orderIDList,
                                          priceType     = 'limit',
                                          volume        = tradingOrders[i]['subOrders']['level0']['volume'],
                                          price         = price_0)
                    tradingOrders[i]['subOrders']['level0']['status'] = 'sended'
                    return
                elif (len(tempCanceledOrder) and self.tradingStartCounter >= 5 and 
                     tradingOrders[i]['subOrders']['level1']['status_u'] and 
                     tradingOrders[i]['subOrders']['level1']['status_d']):
                    ## ---------------------------------------------------------
                    if ( ((h in [9,21] and m < 2) or self.tradingStartCounter <= 30) and
                        any(x in tradingOrders[i]['vtOrderIDList'] for 
                            x in tempCanceledOrder.vtOrderID.values) and 
                       ((datetime.now() - self.tickTimer[vtSymbol]).seconds > 1)):
                        self.sendTradingOrder(tradingOrders = tradingOrders,
                                              orderDict     = tradingOrders[i],
                                              orderIDList   = orderIDList,
                                              priceType     = 'limit',
                                              volume        = remainingVolume,
                                              price         = price_0)
                        return
                    ## ---------------------------------------------------------
                # ---------------------------------------------------------------------------------            

                ## ---------------------------------------------------------------------------------
                for l in ['level2', 'level1']:
                    ## ---------------------------------------------------------
                    if tradingOrders[i]['subOrders'][l]['volume'] == 0:
                        continue
                    ## ---------------------------------------------------------
                    deltaTick = tradingOrders[i]['subOrders'][l]['deltaTick']
                    deltaTick_quick = deltaTick
                    deltaTick_slow  = -deltaTick

                    if tradingOrders[i]['direction'] == 'buy':
                        status_quick    = 'status_u'
                        status_slow     = 'status_d'
                    elif tradingOrders[i]['direction'] == 'short':
                        status_quick    = 'status_d'
                        status_slow     = 'status_u'

                    ## ---------------------------------------------------------
                    if not tradingOrders[i]['subOrders'][l][status_quick]:
                        self.sendTradingOrder(tradingOrders = tradingOrders,
                                              orderDict     = tradingOrders[i],
                                              orderIDList   = orderIDList,
                                              priceType     = 'limit',
                                              volume        = tradingOrders[i]['subOrders'][l]['volume'],
                                              price         = price_0,
                                              addTick       = deltaTick_quick)
                        tradingOrders[i]['subOrders'][l][status_quick] = 'sended'
                        ## 如果真是的分档超过了 3 个层次
                        ## 则需要优先下快速成交的订单
                        if self.realOrderLevel >= 3:
                            continue
                        ## ----
                        ## 要不要继续下单
                        # return
                        ## ----
                        ## -----------------------------------------------------
                    # else:
                    #     ## -------------------------------------------------------------------------
                    #     if not tradingOrders[i]['subOrders']['level0']['status']:
                    #         self.sendTradingOrder(tradingOrders = tradingOrders,
                    #                               orderDict     = tradingOrders[i],
                    #                               orderIDList   = orderIDList,
                    #                               priceType     = 'limit',
                    #                               volume        = tradingOrders[i]['subOrders']['level0']['volume'],
                    #                               price         = price_0)
                    #         tradingOrders[i]['subOrders']['level0']['status'] = 'sended'
                    #         return
                    #     ## -------------------------------------------------------------------------
                    #     elif not tradingOrders[i]['subOrders'][l][status_slow]:
                    #         self.sendTradingOrder(tradingOrders = tradingOrders,
                    #                               orderDict     = tradingOrders[i],
                    #                               orderIDList   = orderIDList,
                    #                               priceType     = 'limit',
                    #                               volume        = tradingOrders[i]['subOrders'][l]['volume'],
                    #                               price         = price_0,
                    #                               addTick       = deltaTick_slow)
                    #         tradingOrders[i]['subOrders'][l][status_slow] = 'sended'
                    #         ## ----
                    #         ## 要不要继续下单
                    #         # return
                    #         ## ----
                    #         ## -----------------------------------------------------

                    if not tradingOrders[i]['subOrders'][l][status_slow]:
                        self.sendTradingOrder(
                            tradingOrders = tradingOrders,
                            orderDict     = tradingOrders[i],
                            orderIDList   = orderIDList,
                            priceType     = 'limit',
                            volume        = tradingOrders[i]['subOrders'][l]['volume'],
                            price         = price_0,
                            addTick       = deltaTick_slow)
                        tradingOrders[i]['subOrders'][l][status_slow] = 'sended'
                        ## -----------------------------------------------------

                ## ---------------------------------------------------------------------------------

            elif (self.tradingBetween and 
                 (datetime.now() - tradingOrders[i]['lastTimer']).seconds >= self.randomNo):
                ## -------------------------------------------------------------
                remainingMinute = (self.tradingCloseMinute2-1 - m) / (self.randomNo / 60.0)
                if remainingMinute == 0:
                    return
                remainingVolume = int(math.ceil(
                    (tradingOrders[i]['volume'] - tempWorkingVolume) / float(remainingMinute))
                    )
                if remainingVolume == 0:
                    return
                ## -------------------------------------------------------------
                self.sendTradingOrder(tradingOrders = tradingOrders,
                                      orderDict     = tradingOrders[i],
                                      orderIDList   = orderIDList,
                                      priceType     = priceType,
                                      volume        = remainingVolume,
                                      price         = price,
                                      addTick       = addTick,
                                      discount      = discount)
                tradingOrders[i]['lastTimer'] = datetime.now()



    def prepareSplit(self, 
                     str vtSymbol, 
                     dict tradingOrders, 
                     list orderIDList, 
                     str priceType = '',
                     int addTick = 0, 
                     float discount = 0.0):
        ## =========================================================================
        cdef list tradingOrderList

        tradingOrderList = [k for k in tradingOrders.keys() 
                             if tradingOrders[k]['vtSymbol'] == vtSymbol and
                                tradingOrders[k]['volume'] != 0]

        if not tradingOrderList:
            return
        # elif ( len(tradingOrderList) == 1 and 
        #        (datetime.now() - tradingOrders[tradingOrderList[0]]['lastTimer']).seconds < self.randomNo ):
        #     return

        allOrders = self.ctaEngine.mainEngine.getAllOrdersDataFrame()

        cdef:
            int tempWorkingVolume = 0,
            float remainingMinute
            int tempAddTick
            float tempDiscount
            int tradingVolume
            int remainingVolume
            int tempVolume
            int h = datetime.now().hour
            int m = datetime.now().minute

        if len(allOrders):
            tempWorkingOrders  = allOrders[(allOrders['vtSymbol'] == vtSymbol) & 
                                           (allOrders['status'].isin([u'未成交',u'部分成交'])) & 
                                           (allOrders['vtOrderID'].isin(orderIDList))]
            tempWorkingVolume = sum(tempWorkingOrders.totalVolume)

        ## =============================================================================
        if self.tradingStartSplit:
            remainingMinute = (self.tradingOpenMinute2 - m) / (self.randomNo / 60.0)
            tempPriceType = 'last'
            tempAddTick = -1
            tempDiscount = 0.0
        elif self.tradingStart:
            remainingMinute = 1
            tempPriceType = 'last'
            tempAddTick = +2
            tempDiscount = 0.0
        elif self.tradingBetween:
            remainingMinute = (self.tradingCloseMinute2-1 - m) / (self.randomNo / 60.0)
            tempPriceType = priceType
            tempAddTick = addTick
            tempDiscount = 0.0
        else:
            return

        if remainingMinute <= 0:
            return
        ## =============================================================================

        cdef str vtOrderID

        for k in tradingOrderList:
            # --------------------------------------------------------
            # 是否需要在 tradingStart 的时候开始追单 
            if ( self.tradingStart and 
                not (h in self.tradingOpenHour and m < self.tradingOpenMinute2) ):
                if len(tempWorkingOrders) != 0:
                    for vtOrderID in tradingOrders[k]['vtOrderIDList']:
                        if vtOrderID in tempWorkingOrders.vtOrderID.values:
                            self.cancelOrder(vtOrderID)
                            tradingOrders[k]['lastTimer'] = datetime.now() - timedelta(seconds = self.randomNo - 1)
                else:
                    tradingOrders[k]['lastTimer'] = datetime.now() - timedelta(seconds = self.randomNo + 1)
            # --------------------------------------------------------

            remainingVolume = tradingOrders[k]['volume'] - tempWorkingVolume

            if ( remainingVolume <= 0 or
                (datetime.now() - tradingOrders[k]['lastTimer']).seconds < self.randomNo ):
                continue

            tempVolume = int(math.ceil(remainingVolume / remainingMinute))

            self.sendTradingOrder(tradingOrders = tradingOrders,
                                  orderDict     = tradingOrders[k],
                                  orderIDList   = orderIDList,
                                  priceType     = tempPriceType,
                                  volume        = tempVolume,
                                  addTick       = tempAddTick)

            tradingOrders[k]['lastTimer'] = datetime.now()
            ## =============================================================================


    ############################################################################
    ## 根据订单的字典格式，发送订单给 CTP
    ## @param stratTrade: 交易事件数据
    ## @param orderDict: 订单的字典格式
    ## @param orderIDList: 订单列表
    ## @param addTick 控制增加的价格
    ############################################################################
    def sendTradingOrder(self, 
                         dict tradingOrders, 
                         dict orderDict, 
                         list orderIDList, 
                         str priceType, 
                         price = None, 
                         int volume = 0, 
                         int addTick = 0, 
                         float discount = 0.0):
        """发送单个合约的订单"""
        cdef:
            str id
            float tempPriceTick
            int tempVolume
            str tempDirection
        ## ---------------------------------------------------------------------

        ## =====================================================================
        ## 基本信息
        ## ---------------------------------------------------------------------
        id = orderDict["vtSymbol"].encode('ascii','ignore')
        tempPriceTick = self.ctaEngine.tickInfo[id]['priceTick']
        tempDirection = orderDict["direction"].encode('ascii','ignore')
        if volume:
            tempVolume = volume
        else:
            tempVolume = orderDict["volume"]

        ## =====================================================================
        ## 定义最佳价格
        ## ---------------------------------------------------------------------
        if priceType == "best":
            if tempDirection in ["buy","cover"]:
                tempBestPrice = self.ctaEngine.lastTickDict[id]["bidPrice1"]
            elif tempDirection in ["sell","short"]:
                tempBestPrice = self.ctaEngine.lastTickDict[id]["askPrice1"]
        elif priceType == "chasing":
            if tempDirection in ["buy","cover"]:
                tempBestPrice = self.ctaEngine.lastTickDict[id]["askPrice1"]
            elif tempDirection in ["sell","short"]:
                tempBestPrice = self.ctaEngine.lastTickDict[id]["bidPrice1"]
        elif priceType == "last":
            tempBestPrice = self.ctaEngine.lastTickDict[id]["lastPrice"]
        elif priceType == "open":
            tempBestPrice = self.ctaEngine.lastTickDict[id]["openPrice"]
        elif priceType == "upper":
            tempBestPrice = self.ctaEngine.lastTickDict[id]["upperLimit"]
        elif priceType == "lower":
            tempBestPrice = self.ctaEngine.lastTickDict[id]["lowerLimit"]
        elif priceType == "limit":  ## 指定价格下单
            if price:
                tempBestPrice = price
            else:
                print u'错误的价格输入'
                return None
        ## =====================================================================
        
        ## =====================================================================
        ## 限定价格在 UpperLimit 和 LowerLimit 之间
        ## ---------------------------------------------------------------------
        if tempDirection in ["buy","cover"]:
            tempPrice = self.priceBetweenUpperLower(
                tempBestPrice * (1-discount) + tempPriceTick * addTick, id)
        elif tempDirection in ["short","sell"]:
            tempPrice = self.priceBetweenUpperLower(
                tempBestPrice * (1+discount) - tempPriceTick * addTick, id)
        ## =====================================================================

        ## =====================================================================
        ## 开始下单
        ## ---------------------------------------------------------------------
        if tempDirection == "buy":
            vtOrderIDList = self.buy(vtSymbol = id, price = tempPrice, volume = tempVolume)
        elif tempDirection == "short":
            vtOrderIDList = self.short(vtSymbol = id, price = tempPrice, volume = tempVolume)
        elif tempDirection == "cover":
            vtOrderIDList = self.cover(vtSymbol = id, price = tempPrice, volume = tempVolume)
        elif tempDirection == "sell":
            vtOrderIDList = self.sell(vtSymbol = id, price = tempPrice, volume = tempVolume)
        ## =====================================================================

        ## =====================================================================
        ## 更新信息
        ## ---------------------------------------------------------------------
        orderIDList.extend(vtOrderIDList)

        tradingOrders[id+'-'+tempDirection]['vtOrderIDList'].extend(vtOrderIDList)

        self.tickTimer[id]= datetime.now()
        ## ---------------------------------------------------------------------
        
        ## ---------------------------------------------------------------------
        ## orderNo: 已经下单的次数计数
        ## 未来可以用于控制订单
        # if 'orderNo' not in tradingOrders[tempKey].keys():
        #     tradingOrders[tempKey]['orderNo'] = 1
        # else:
        #     tradingOrders[tempKey]['orderNo'] += 1
        ## ---------------------------------------------------------------------

    ############################################################################
    ## 更新 交易状态
    ## self.trading
    ## self.tradingStart
    ## self.tradingEnd
    ## self.tradingBetween
    ############################################################################
    def updateTradingStatus(self):
        """调整交易状态"""
        cdef:
            int h = datetime.now().hour
            int m = datetime.now().minute
            int s = datetime.now().second
        ## =====================================================================
        ## 启动尾盘交易
        ## =====================================================================
        if ( (h in [8,20] and m >= 59 and s >= 55) or 
             (h in [21,22,23,0,1,2]) or 
             (9 <= h <= (self.tradingCloseHour-1)) or 
             (h == self.tradingCloseHour and m < self.tradingCloseMinute1-10) ):
            self.tradingStart = True
        else:
            self.tradingStart = False

        if ( (h in self.tradingOpenHour) and 
            ((self.tradingOpenMinute1 <= m < self.tradingOpenMinute2-1) or 
             (m == self.tradingOpenMinute2-1 and s < 50)) ):
            self.tradingStartSplit = True
        else:
            self.tradingStartSplit = False

        ## ---------------------------------------------------------------------
        if (h == self.tradingCloseHour and 
           (self.tradingCloseMinute1+1) <= m <= (self.tradingCloseMinute2-1)):
            self.tradingBetween = True
        else:
            self.tradingBetween = False

        ## ---------------------------------------------------------------------
        if ( h == self.tradingCloseHour and 
             m == self.tradingCloseMinute2 and 
            (s > max(30, 59 - max(15, len(self.tradingOrdersClose)))) ):
            self.tradingEnd = True
        else:
            self.tradingEnd = False
        ## ---------------------------------------------------------------------

        ## =====================================================================
        ## 如果是开盘交易
        ## 则取消开盘交易的所有订单
        if ( (h == self.tradingCloseHour) and 
             (m in [self.tradingCloseMinute1, self.tradingCloseMinute2]) and 
            s <= 10 and (s % 5 == 0)):
            ## -----------------------------------------------------------------
            if (len(self.vtOrderIDListOpen) != 0 or 
                len(self.vtOrderIDListClose) != 0 or 
                len(self.vtOrderIDListUpperLower) != 0):
                allOrders = self.ctaEngine.mainEngine.getAllOrdersDataFrame()
                for vtOrderID in self.vtOrderIDListOpen + \
                                 self.vtOrderIDListClose + \
                                 self.vtOrderIDListUpperLower + \
                                 self.vtOrderIDListUpperLowerCum + \
                                 self.vtOrderIDListUpperLowerTempCum + \
                                 self.vtOrderIDListWinner + \
                                 self.vtOrderIDListTempWinner:
                    if vtOrderID in allOrders.loc[allOrders.status.isin([u'未成交',u'部分成交'])].vtOrderID.values:
                            self.cancelOrder(vtOrderID)
            ## -----------------------------------------------------------------
        ## =====================================================================


        ## =====================================================================
        if (h in self.tradingOpenHour and 
            m == self.tradingOpenMinute2-1 and
            s >= 50 and s%5 == 0 and 
            len(self.vtOrderIDListOpenSplit) != 0):
            allOrders = self.ctaEngine.mainEngine.getAllOrdersDataFrame()
            for vtOrderID in self.vtOrderIDListOpenSplit:
                if vtOrderID in allOrders.loc[allOrders.status.isin([u'未成交',u'部分成交'])].vtOrderID.values:
                        self.cancelOrder(vtOrderID)
        ## =====================================================================

        ## =====================================================================
        ## 生成收盘交易的订单
        if (h == self.tradingCloseHour and 
            m in [self.tradingCloseMinute1, (self.tradingCloseMinute2)] and 
            10 <= s <= 20 and 
            self.ctaEngine.mainEngine.multiStrategy and 
            (s == 19 or s % 5 == 0)):
            self.writeCtaLog('Rscript end_signal.R')
            subprocess.call(['Rscript',
                             os.path.join(self.ctaEngine.mainEngine.ROOT_PATH,
                             'vnpy/trader/app/ctaStrategy/Rscripts',
                             'end_signal.R'),
                             self.ctaEngine.mainEngine.ROOT_PATH, 
                             self.ctaEngine.mainEngine.dataBase], 
                             shell = False)

        ## =====================================================================
        ## 从 MySQL 数据库提取尾盘需要平仓的持仓信息
        ## postionInfoClose
        ## =====================================================================
        if ( (h == self.tradingCloseHour and m == self.tradingCloseMinute1) or
             (h == self.tradingCloseHour+1 and m <= 3 ) and 
             (30 <= s <= 59 and s%10 == 0) ):
            ## -----------------------------------------------------------------
            try:
                conn = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
                cursor = conn.cursor()
                cursor.execute("""
                                TRUNCATE TABLE workingInfo
                               """)
                conn.commit()
                conn.close()
            except:
                self.writeCtaLog(u'workingInfo 清理数据 出错',
                                 logLevel = ERROR) 
            ## -----------------------------------------------------------------  


    ############################################################################
    ## 更新 workingInfo
    ############################################################################
    def updateWorkingInfo(self, dict tradingOrders, str stage):
        """
        更新 workingInfo 表格
        """
        if not tradingOrders:
            return
        
        tempWorkingInfo = vtFunction.dbMySQLQuery(self.ctaEngine.mainEngine.dataBase,
                                    """
                                    SELECT *
                                    FROM workingInfo
                                    WHERE strategyID = '%s'
                                    AND TradingDay = '%s'
                                    AND stage = '%s'
                                    """ %(self.strategyID, self.ctaEngine.tradingDay, stage))

        cdef:
            list dfHeader = ['TradingDay','strategyID','vtSymbol','vtOrderIDList',
                             'orderType','volume','stage']
            list dfData   = []

        for k in tradingOrders.keys():
            temp = copy(tradingOrders[k])
            if not temp['vtOrderIDList']:
                continue
            temp['strategyID'] = self.strategyID
            temp['orderType'] = temp['direction']
            temp['vtOrderIDList'] = ujson.dumps(temp['vtOrderIDList'])
            temp['stage'] = stage
            dfData.append([temp[kk] for kk in dfHeader])
        df = pd.DataFrame(dfData, columns = dfHeader)

        ## ---------------------------------------------------------------------
        try:
            conn = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
            cursor = conn.cursor()
            cursor.execute("""
                            DELETE FROM workingInfo
                            WHERE strategyID = '%s'
                            AND stage = '%s'
                           """ %(self.strategyID, stage))
            conn.commit()
            conn.close()
        except:
            self.writeCtaLog(u'workingInfo 活跃订单 写入 MySQL 数据库出错',
                                 logLevel = ERROR)
        ## ---------------------------------------------------------------------
    
        self.saveMySQL(df = df, 
                       tbl = 'workingInfo', 
                       over = 'append',
                       sourceID = 'ctaTemplate.updateWorkingInfo()')
        ## ---------------------------------------------------------------------


    ############################################################################
    ## 更新交易记录的数据表
    ############################################################################
    def updateTradingInfo(self, df):
        """更新交易记录"""
        self.saveMySQL(df = df, 
                       tbl = 'tradingInfo',
                       over = 'append')


    ############################################################################
    ## 更新订单表
    ############################################################################
    def updateTradingOrdersTable(self, stratTrade):
        """
        更新交易订单表
        """
        ## =====================================================================

        cdef:
            str tempDirection
            int tempVolume
            int i

        ## ---------------------------------------------------------------------
        if self.stratTrade['offset'] == u'开仓':
            if self.stratTrade['direction'] == 'long':
                tempDirection = 'buy'
            elif self.stratTrade['direction'] == 'short':
                tempDirection = 'short'
        elif self.stratTrade['offset'] in [u'平仓', u'平昨', u'平今']:
            if self.stratTrade['direction'] == 'long':
                tempDirection = 'cover'
            elif self.stratTrade['direction'] == 'short':
                tempDirection = 'sell'
        ## ---------------------------------------------------------------------
        
        ## =====================================================================
        mysqlInfoTradingOrders = vtFunction.dbMySQLQuery(self.ctaEngine.mainEngine.dataBase,
                                """
                                SELECT *
                                FROM tradingOrders
                                WHERE strategyID = '%s'
                                AND InstrumentID = '%s'
                                AND orderType = '%s'
                                """ %(self.strategyID,self.stratTrade['vtSymbol'],
                                      tempDirection))
        if not len(mysqlInfoTradingOrders):
            return
        
        ## ---------------------------------------------------------------------
        conn = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
        cursor = conn.cursor()
        
        for i in xrange(len(mysqlInfoTradingOrders)):
            tempVolume = mysqlInfoTradingOrders.at[i,'volume'] - self.stratTrade['volume']
            if tempVolume == 0:
                cursor.execute("""
                                DELETE FROM tradingOrders
                                WHERE strategyID = %s
                                AND InstrumentID = %s
                                AND volume = %s
                                AND orderType = %s
                               """, (self.strategyID, self.stratTrade['vtSymbol'],
                                mysqlInfoTradingOrders.at[i,'volume'],
                                tempDirection))
                conn.commit()
            else:
                cursor.execute("""
                                UPDATE tradingOrders
                                SET volume = %s
                                WHERE strategyID = %s
                                AND InstrumentID = %s
                                AND volume = %s
                                AND orderType = %s
                               """, (tempVolume, self.strategyID, 
                                self.stratTrade['vtSymbol'],
                                mysqlInfoTradingOrders.at[i,'volume'],
                                tempDirection))
                conn.commit()
        ## ---------------------------------------------------------------------
        conn.close()

    ############################################################################
    ## 更新订单字典
    ## orderInfo
    ############################################################################
    def updateOrderInfo(self):
        """
        更新订单记录表 orderInfo
        """
        ## =====================================================================
        ## 1. 更新账户信息
        ## 2. 更新 orderInfo
        ## =====================================================================

        ## 把账户信息写入 MysQL 数据库
        ## =====================================================================
        self.ctaEngine.mainEngine.dataEngine.getIndicatorInfo(
            dbName = self.ctaEngine.mainEngine.dataBase,
            initialCapital = self.ctaEngine.mainEngine.initialCapital,
            flowCapital = self.ctaEngine.mainEngine.flowCapital)
        ## =====================================================================
        ## 把所有下单记录写入 MySQL 数据库
        mysqlOrderInfo = vtFunction.dbMySQLQuery(self.ctaEngine.mainEngine.dataBase,
                        """
                        SELECT *
                        FROM orderInfo
                        WHERE strategyID = '%s'
                        AND TradingDay = %s
                       """ %(self.strategyID, self.ctaEngine.tradingDay))
        stratOrderIDListAll = self.vtOrderIDListOpen + self.vtOrderIDListClose + self.vtOrderIDListFailedInfo + self.vtOrderIDListUpperLower
        tempOrderIDList = [k for k in stratOrderIDListAll if k not in mysqlOrderInfo['vtOrderID'].values]
        ## ---------------------------------------------------------------------
        if len(tempOrderIDList) == 0:
            return 
        ## ---------------------------------------------------------------------
        df = pd.DataFrame([], columns = self.orderInfoFields)
        for i in tempOrderIDList:
            tempOrderInfo = self.ctaEngine.mainEngine.getAllOrdersDataFrame().loc[self.ctaEngine.mainEngine.getAllOrdersDataFrame().vtOrderID == i]
            tempOrderInfo['strategyID'] = self.strategyID
            df = df.append(tempOrderInfo[self.orderInfoFields], ignore_index=True)
        df = df[self.orderInfoFields]
        df['TradingDay'] = self.ctaEngine.tradingDate
        df['strategyID'] = self.strategyID
        df = df[['TradingDay'] + self.orderInfoFields]
        ## 改名字
        df.columns.values[3] = 'InstrumentID'
        if len(mysqlOrderInfo) != 0:
            df = df.append(mysqlOrderInfo, ignore_index=True)
        if len(df) != 0:
            ## -----------------------------------------------------------------
            try:
                conn = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
                cursor = conn.cursor()
                ## 清空记录
                cursor.execute("""
                                DELETE FROM orderInfo
                                WHERE strategyID = %s
                                AND TradingDay = %s
                               """, (self.strategyID, self.ctaEngine.tradingDay))
                conn.commit()
                conn.close()
                ## 写入记录
                ## 去掉重复的行
                df = df.drop_duplicates().reset_index(drop = True)
                self.saveMySQL(df = df, 
                               tbl = 'orderInfo', 
                               over = 'append',
                               sourceID = 'ctaTemplate.updateOrderInfo()')
            except:
                self.writeCtaLog(u'orderInfo 委托订单 写入 MySQL 数据库出错',
                                     logLevel = ERROR)
        ## =====================================================================


    ############################################################################
    ## 更新失败未成交订单
    ############################################################################
    def updateFailedInfo(self, dict tradingOrders, dict tradedOrders):
        """更新收盘后未成交的订单"""

        ## 提取失败订单
        self.failedOrders = {k:tradingOrders[k] 
                             for k in tradingOrders.keys() if k not in tradedOrders.keys()}
        ## -----------------------------------------------------------------
        if not self.failedOrders:
            return
        ## -----------------------------------------------------------------

        ## =============================================================================
        dfData = []
        ## -------------------------------------------------------------
        for k in self.failedOrders.keys():
            ## ---------------------------------------------------------
            if self.failedOrders[k]['direction'] == 'buy':
                tempDirection = 'long'
                tempOffset    = 'open'
            elif self.failedOrders[k]['direction'] == 'sell':
                tempDirection    = 'short'
                tempDirectionPos = 'long'
                tempOffset       = 'close'
            elif self.failedOrders[k]['direction'] == 'short':
                tempDirection = 'short'
                tempOffset    = 'open'
            elif self.failedOrders[k]['direction'] == 'cover':
                tempDirection    = 'long'
                tempDirectionPos = 'short'
                tempOffset       = 'close'
            ## ---------------------------------------------------------
            tempRes = [self.strategyID, self.failedOrders[k]['vtSymbol'], 
                       self.failedOrders[k]['TradingDay'], 
                       tempDirection, tempOffset, self.failedOrders[k]['volume']]
            dfData.append(tempRes)
            ## ---------------------------------------------------------

            ## -----------------------------------------------------------------------------
            ## 只有需要平仓的，才需要从 positionInfo 数据表剔除
            ## -----------------------------------------------------------------------------
            if tempOffset == 'close':
                try:
                    conn = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
                    cursor = conn.cursor()
                    cursor.execute("""
                                    DELETE FROM positionInfo
                                    WHERE strategyID = %s
                                    AND InstrumentID = %s
                                    AND TradingDay = %s
                                    AND direction  = %s
                                   """, (self.strategyID, self.failedOrders[k]['vtSymbol'], self.failedOrders[k]['TradingDay'], tempDirectionPos))
                    conn.commit()
                    conn.close()
                except:
                    None
            ## -------------------------------------------------------------------------
        try:
            df = pd.DataFrame(dfData, columns = self.failedInfoFields)
            ## -------------------------------------------------------------
            conn = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
            cursor = conn.cursor()
            cursor.execute("""
                            DELETE FROM failedInfo
                            WHERE strategyID = %s
                            AND TradingDay = %s
                           """,(self.strategyID, self.ctaEngine.tradingDay))
            conn.commit()
            conn.close()
            self.saveMySQL(df = df, 
                           tbl = 'failedInfo', 
                           over = 'append',
                           sourceID = 'ctaTemplate.updateFailedInfo()')
        except:
            self.writeCtaLog(u'failedInfo 失败订单 写入 MySQL 数据库出错',
                                 logLevel = ERROR)
        ## =====================================================================

    ############################################################################
    ## 更新最新价格字典
    ## lastInfo
    ############################################################################
    def updateLastTickInfo(self):
        """处理最新价格的数据表"""
        ## ---------------------------------------------------------------------
        ## 保存 lastTick
        if not self.ctaEngine.lastTickDict:
            return

        cdef:
            list v,k

        ## ---------------------------------------------------------------------
        if not (15 < datetime.now().hour < 20):
            try:
                v = [self.ctaEngine.lastTickDict[k].values() 
                        for k in self.ctaEngine.lastTickDict.keys()]
                k = [self.ctaEngine.lastTickDict[k].keys() 
                        for k in self.ctaEngine.lastTickDict.keys()]
                df = pd.DataFrame(v, columns = k[0])
                df.rename(columns={'datetime': 'updateTime'}, inplace=True)
                df['TradingDay'] = self.ctaEngine.tradingDay

                self.saveMySQL(df = df, 
                               tbl = 'lastTickInfo', 
                               over = 'replace',
                               sourceID = 'ctaTemplate.updateLastTickInfo()')
            except:
                self.writeCtaLog(u'updateLastTickInfo 更新 MySQL 数据库出错',
                                 logLevel = ERROR)
        else:
            try:
                conn = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
                cursor = conn.cursor()
                cursor.execute("""
                                TRUNCATE TABLE lastTickInfo
                               """)
                conn.commit()
                conn.close()
            except:
                self.writeCtaLog(u'updateLastTickInfo 清空 MySQL 数据库出错',
                                 logLevel = ERROR)
        ## ---------------------------------------------------------------------


    ############################################################################
    ## 订单成交后
    ## 处理 开仓的订单
    ############################################################################
    def processOffsetOpen(self, stratTrade):
        """处理开仓订单"""
       
        ## =====================================================================
        ## 1. 更新 mysql.positionInfo
        ## =====================================================================
        ## mysqlPositionInfo: 存储在 mysql 数据库的持仓信息，需要更新
        mysqlPositionInfo = vtFunction.dbMySQLQuery(
            self.ctaEngine.mainEngine.dataBase,
            """
            SELECT *
            FROM positionInfo
            WHERE strategyID = '%s'
            """ %(self.strategyID))

        ## 看看是不是已经在数据库里面了
        tempPosInfo = mysqlPositionInfo[(mysqlPositionInfo.InstrumentID == stratTrade['InstrumentID']) &\
                                        (mysqlPositionInfo.TradingDay == stratTrade['TradingDay']) &\
                                        (mysqlPositionInfo.direction == stratTrade['direction'])]
        ## ---------------------------------------------------------------------
        cdef:
            list tempFields
        ## ---------------------------------------------------------------------
        if len(tempPosInfo) == 0:
            ## 如果不在
            ## 则直接添加过去即可
            try:
                tempFields = ['strategyID','InstrumentID','TradingDay','direction','volume']
                tempRes = pd.DataFrame([[stratTrade[k] for k in tempFields]], columns = tempFields)
                self.saveMySQL(df = tempRes, 
                               tbl = 'positionInfo', 
                               over = 'append',
                               sourceID = 'ctaTemplate.processOffsetOpen()')
            except:
                self.writeCtaLog(u'processOffsetOpen 开仓订单 写入 MySQL 数据库出错',
                                 logLevel = ERROR)
        else:
            ## 如果在
            ## 则需要更新数据
            mysqlPositionInfo.at[tempPosInfo.index[0], 'volume'] += stratTrade['volume']
            mysqlPositionInfo = mysqlPositionInfo.loc[mysqlPositionInfo.volume != 0]
            try:
                conn   = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
                cursor = conn.cursor()
                cursor.execute("""
                                DELETE FROM positionInfo
                                WHERE strategyID = '%s'
                               """ %(self.strategyID))
                conn.commit()
                conn.close()
                self.saveMySQL(df = mysqlPositionInfo, 
                               tbl = 'positionInfo', 
                               over = 'append',
                               sourceID = 'ctaTemplate.processOffsetOpen()')
            except:
                self.writeCtaLog(u'processOffsetOpen 开仓订单 写入 MySQL 数据库出错',
                                 logLevel = ERROR)
        ## -----------------------------------------------------------------


    ############################################################################
    ## 订单成交后
    ## 处理 平仓的订单
    ############################################################################
    def processOffsetClose(self, stratTrade):
        """处理开仓订单"""
        cdef:
            str tempDirectionPos
            int tempResVolume
            int i
        ## ---------------------------------------------------------------------
        if stratTrade['direction'] == 'long':
            tempDirectionPos = 'short'
        elif stratTrade['direction'] == 'short':
            tempDirectionPos = 'long'
        ## ---------------------------------------------------------------------

        ## =====================================================================
        ## mysqlPositionInfo: 存储在 mysql 数据库的持仓信息，需要更新
        mysqlPositionInfo = vtFunction.dbMySQLQuery(
            self.ctaEngine.mainEngine.dataBase,
            """
            SELECT *
            FROM positionInfo
            WHERE strategyID = '%s'
            """ %(self.strategyID))
        tempPosInfo = mysqlPositionInfo[(mysqlPositionInfo.InstrumentID == stratTrade['InstrumentID']) &\
                                        (mysqlPositionInfo.direction == tempDirectionPos)].sort_values(by='TradingDay', ascending = True)
        ## ---------------------------------------------------------------------------------
        for i in xrange(len(tempPosInfo)):
            tempResVolume = tempPosInfo.loc[tempPosInfo.index[i],'volume'] - stratTrade['volume']
            mysqlPositionInfo.at[tempPosInfo.index[i], 'volume'] = tempResVolume
            if tempResVolume >= 0:
                break
        ## ---------------------------------------------------------------------------------
        mysqlPositionInfo = mysqlPositionInfo.loc[mysqlPositionInfo.volume > 0]   
        ## ---------------------------------------------------------------------
        ## ---------------------------------------------------------------------
        try:
            conn   = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
            cursor = conn.cursor()
            cursor.execute("""
                            DELETE FROM positionInfo
                            WHERE strategyID = '%s'
                           """ %(self.strategyID))
            conn.commit()
            conn.close()
            self.saveMySQL(df = mysqlPositionInfo, 
                           tbl = 'positionInfo', 
                           over = 'append',
                           sourceID = 'ctaTemplate.processOffsetClose()')
        except:
            self.writeCtaLog(u'processOffsetClose 平仓订单 写入 MySQL 数据库出错', 
                               logLevel = ERROR)
        ## =========================================================================


    ############################################################################
    ## 订单成交后
    ## 处理 failedInfo
    ############################################################################
    def processTradingOrdersFailedInfo(self, stratTrade):
        """处理昨日未成交失败的订单，需要更新 failedInfo"""
        mysqlFailedInfo = vtFunction.dbMySQLQuery(self.ctaEngine.mainEngine.dataBase,
                """
                SELECT *
                FROM failedInfo
                WHERE strategyID = '%s'
                """ %(self.strategyID))
        ## ---------------------------------------------------------------------
        if len(mysqlFailedInfo) == 0:
            return
        ## ---------------------------------------------------------------------

        ## ---------------------------------------------------------------------
        if stratTrade['offset'] in [u'平仓', u'平昨', u'平今']:
            tempOffset = 'close'
        tempPosInfo = mysqlFailedInfo.loc[mysqlFailedInfo.InstrumentID == stratTrade['InstrumentID']][\
                                          mysqlFailedInfo.direction == stratTrade['direction']][\
                                          mysqlFailedInfo.offset == tempOffset]

        mysqlFailedInfo.at[tempPosInfo.index[0], 'volume'] -= stratTrade['volume']
        mysqlFailedInfo = mysqlFailedInfo.loc[mysqlFailedInfo.volume != 0]
        ## ---------------------------------------------------------------------
        ## ---------------------------------------------------------------------
        try:
            conn   = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
            cursor = conn.cursor()
            cursor.execute("""
                            DELETE FROM failedInfo
                            WHERE strategyID = '%s'
                           """ %(self.strategyID))
            conn.commit()
            conn.close()
            self.saveMySQL(df = mysqlFailedInfo, 
                           tbl = 'failedInfo', 
                           over = 'append',
                           sourceID = 'ctaTemplate.processTradingOrdersFailedInfo()')
        except:
            self.writeCtaLog(u'processTradingOrdersFailedInfo 昨日未成交订单 写入 MySQL 数据库出错',
                             logLevel = ERROR)
        ## ---------------------------------------------------------------------

    ############################################################################
    ## 从 MySQL 数据库读取数据
    ############################################################################
    def fetchMySQL(self, query):
        df = vtFunction.fetchMySQL(db    = self.ctaEngine.mainEngine.dataBase, 
                                   query = query)
        return(df)

    ############################################################################
    ## 保存数据 DataFrame 格式到 MySQL
    ############################################################################
    def saveMySQL(self, df, tbl, str over, str sourceID = ''):
        """
            保存 DataFrame 格式数据到 MySQL,
            @param
                df  : 数据
                tbl : 表格
                over: 写入方式
                    : 1. 'append'： 添加
                    : 2. 'replace': 替代
        """
        if over == 'replace':
            over = 'append'
            try:
                conn = vtFunction.dbMySQLConnect(self.ctaEngine.mainEngine.dataBase)
                cursor = conn.cursor()
                cursor.execute("""
                                TRUNCATE TABLE %s
                               """ %tbl)
                conn.commit()
                conn.close()
            except:
                print 'ctaTemplate.saveMySQL() 写入数据库失败'
        ## -------------------------------------------------------------
        vtFunction.saveMySQL(df   = df, 
                             db   = self.ctaEngine.mainEngine.dataBase, 
                             tbl  = tbl, 
                             over = over,
                             sourceID = sourceID)
        ## -------------------------------------------------------------


## =============================================================================
## william
## 生成 Bar 数据
## =============================================================================
class BarGenerator(object):
    """
    K线合成器，支持：
    1. 基于Tick合成1分钟K线
    2. 默认生成 1 分钟的数据，即 xmin = 0
    3. 基于1分钟K线合成X分钟K线（X可以是2、3、5、10、15、30    ）
    """

    #----------------------------------------------------------------------
    def __init__(self, onBar, xmin=0, onXminBar=None):
        """Constructor"""
        ## ------------------------------------------
        self.bar = {}           ## Bar 数据字典 
                                ## key: tick.vtSymbol 
                                ## value: VtBarData()
        self.tick = {}          ## Tick 数据字典,
                                ## key: tick.vtSymbol 
                                ## value: tick
        self.newMinute = {}     ## 是否是新的分钟数据, 默认不是新的一分钟
                                ## key: tick.vtSymbol
                                ## value: True, False
        ## ------------------------------------------

        self.onBar = onBar          # 1分钟K线回调函数
        
        self.xminBar = None         # X分钟K线对象
        self.xmin = xmin            # X的值
        self.onXminBar = onXminBar  # X分钟K线的回调函数

        
    #----------------------------------------------------------------------
    def updateTick(self, tick):
        """TICK更新"""
        id = tick.vtSymbol
        self.newMinute[id] = False  # 默认不是新的一分钟

        # 尚未创建对象
        if id not in self.bar.keys():
            self.bar[id] = VtBarData()
            self.newMinute[id] = True
        # 新的一分钟
        elif self.bar[id].datetime.minute != tick.datetime.minute:
            # 生成上一分钟K线的时间戳
            # 将秒和微秒设为0
            self.bar[id].datetime = self.bar[id].datetime.replace(second=0, microsecond=0)  
            self.bar[id].date = self.bar[id].datetime.strftime('%Y%m%d')
            self.bar[id].time = self.bar[id].datetime.strftime('%H:%M:%S.%f')
            
            # 推送已经结束的上一分钟K线
            self.onBar(self.bar[id])
            
            # 创建新的K线对象
            self.bar[id] = VtBarData()
            self.newMinute[id] = True
            
        # 初始化新一分钟的K线数据
        if self.newMinute[id]:
            self.bar[id].vtSymbol = tick.vtSymbol
            self.bar[id].symbol = tick.symbol
            self.bar[id].exchange = tick.exchange

            self.bar[id].open = tick.lastPrice
            self.bar[id].high = tick.lastPrice
            self.bar[id].low = tick.lastPrice
        # 累加更新老一分钟的K线数据
        else:                                   
            self.bar[id].high = max(self.bar[id].high, tick.lastPrice)
            self.bar[id].low = min(self.bar[id].low, tick.lastPrice)

        # 通用更新部分
        self.bar[id].close = tick.lastPrice        
        self.bar[id].datetime = tick.datetime  
        # self.bar[id].openInterest = tick.openInterest
        
        if id in self.tick.keys():
            self.bar[id].volume += (tick.volume - self.tick[id].volume) 
            self.bar[id].turnover += (tick.turnover - self.tick[id].turnover) 

        # 缓存Tick
        self.tick[id] = tick

    #----------------------------------------------------------------------
    def updateBar(self, bar):
        """1分钟K线更新"""
        # 尚未创建对象
        if not self.xminBar:
            self.xminBar = VtBarData()
            
            self.xminBar.vtSymbol = bar.vtSymbol
            self.xminBar.symbol = bar.symbol
            self.xminBar.exchange = bar.exchange
        
            self.xminBar.open = bar.open
            self.xminBar.high = bar.high
            self.xminBar.low = bar.low            
            
            # 以第一根分钟K线的开始时间戳作为X分钟线的时间戳
            self.xminBar.datetime = bar.datetime    
        else:
            # 累加老K线
            self.xminBar.high = max(self.xminBar.high, bar.high)
            self.xminBar.low = min(self.xminBar.low, bar.low)
    
        # 通用部分
        self.xminBar.close = bar.close        
        self.xminBar.openInterest = bar.openInterest
        self.xminBar.volume += int(bar.volume)                
            
        # X分钟已经走完
        if not (bar.datetime.minute + 1) % self.xmin:   # 可以用X整除
            # 生成上一X分钟K线的时间戳
            self.xminBar.datetime = self.xminBar.datetime.replace(second=0, microsecond=0)  # 将秒和微秒设为0
            self.xminBar.date = self.xminBar.datetime.strftime('%Y%m%d')
            self.xminBar.time = self.xminBar.datetime.strftime('%H:%M:%S.%f')
            
            # 推送
            self.onXminBar(self.xminBar)
            
            # 清空老K线缓存对象
            self.xminBar = None


########################################################################
class ArrayManager(object):
    """
    K线序列管理工具，负责：
    1. K线时间序列的维护
    2. 常用技术指标的计算
    """

    #----------------------------------------------------------------------
    def __init__(self, size=100):
        """Constructor"""
        self.count = 0                      # 缓存计数
        self.size = size                    # 缓存大小
        self.inited = False                 # True if count>=size
        
        self.openArray = np.zeros(size)     # OHLC
        self.highArray = np.zeros(size)
        self.lowArray = np.zeros(size)
        self.closeArray = np.zeros(size)
        self.volumeArray = np.zeros(size)
        
    #----------------------------------------------------------------------
    def updateBar(self, bar):
        """更新K线"""
        self.count += 1
        if not self.inited and self.count >= self.size:
            self.inited = True
        
        self.openArray[0:self.size-1] = self.openArray[1:self.size]
        self.highArray[0:self.size-1] = self.highArray[1:self.size]
        self.lowArray[0:self.size-1] = self.lowArray[1:self.size]
        self.closeArray[0:self.size-1] = self.closeArray[1:self.size]
        self.volumeArray[0:self.size-1] = self.volumeArray[1:self.size]
    
        self.openArray[-1] = bar.open
        self.highArray[-1] = bar.high
        self.lowArray[-1] = bar.low        
        self.closeArray[-1] = bar.close
        self.volumeArray[-1] = bar.volume
        
    #----------------------------------------------------------------------
    @property
    def open(self):
        """获取开盘价序列"""
        return self.openArray
        
    #----------------------------------------------------------------------
    @property
    def high(self):
        """获取最高价序列"""
        return self.highArray
    
    #----------------------------------------------------------------------
    @property
    def low(self):
        """获取最低价序列"""
        return self.lowArray
    
    #----------------------------------------------------------------------
    @property
    def close(self):
        """获取收盘价序列"""
        return self.closeArray
    
    #----------------------------------------------------------------------
    @property    
    def volume(self):
        """获取成交量序列"""
        return self.volumeArray
    
    #----------------------------------------------------------------------
    def sma(self, n, array=False):
        """简单均线"""
        result = talib.SMA(self.close, n)
        if array:
            return result
        return result[-1]
        
    #----------------------------------------------------------------------
    def std(self, n, array=False):
        """标准差"""
        result = talib.STDDEV(self.close, n)
        if array:
            return result
        return result[-1]
    
    #----------------------------------------------------------------------
    def cci(self, n, array=False):
        """CCI指标"""
        result = talib.CCI(self.high, self.low, self.close, n)
        if array:
            return result
        return result[-1]
        
    #----------------------------------------------------------------------
    def atr(self, n, array=False):
        """ATR指标"""
        result = talib.ATR(self.high, self.low, self.close, n)
        if array:
            return result
        return result[-1]
        
    #----------------------------------------------------------------------
    def rsi(self, n, array=False):
        """RSI指标"""
        result = talib.RSI(self.close, n)
        if array:
            return result
        return result[-1]
    
    #----------------------------------------------------------------------
    def macd(self, fastPeriod, slowPeriod, signalPeriod, array=False):
        """MACD指标"""
        macd, signal, hist = talib.MACD(self.close, fastPeriod,
                                        slowPeriod, signalPeriod)
        if array:
            return macd, signal, hist
        return macd[-1], signal[-1], hist[-1]
    
    #----------------------------------------------------------------------
    def adx(self, n, array=False):
        """ADX指标"""
        result = talib.ADX(self.high, self.low, self.close, n)
        if array:
            return result
        return result[-1]
    
    #----------------------------------------------------------------------
    def boll(self, n, dev, array=False):
        """布林通道"""
        mid = self.sma(n, array)
        std = self.std(n, array)
        
        up = mid + std * dev
        down = mid - std * dev
        
        return up, down    
    
    #----------------------------------------------------------------------
    def keltner(self, n, dev, array=False):
        """肯特纳通道"""
        mid = self.sma(n, array)
        atr = self.atr(n, array)
        
        up = mid + atr * dev
        down = mid - atr * dev
        
        return up, down
    
    #----------------------------------------------------------------------
    def donchian(self, n, array=False):
        """唐奇安通道"""
        up = talib.MAX(self.high, n)
        down = talib.MIN(self.low, n)
        
        if array:
            return up, down
        return up[-1], down[-1]
