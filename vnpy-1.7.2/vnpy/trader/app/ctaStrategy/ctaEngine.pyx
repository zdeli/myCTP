# encoding: UTF-8

'''
本文件中实现了CTA策略引擎，针对CTA类型的策略，抽象简化了部分底层接口的功能。

关于平今和平昨规则：
1. 普通的平仓OFFSET_CLOSET等于平昨OFFSET_CLOSEYESTERDAY
2. 只有上期所的品种需要考虑平今和平昨的区别
3. 当上期所的期货有今仓时，调用Sell和Cover会使用OFFSET_CLOSETODAY，否则
   会使用OFFSET_CLOSE
4. 以上设计意味着如果Sell和Cover的数量超过今日持仓量时，会导致出错（即用户
   希望通过一个指令同时平今和平昨）
5. 采用以上设计的原因是考虑到vn.trader的用户主要是对TB、MC和金字塔类的平台
   感到功能不足的用户（即希望更高频的交易），交易策略不应该出现4中所述的情况
6. 对于想要实现4中所述情况的用户，需要实现一个策略信号引擎和交易委托引擎分开
   的定制化统结构（没错，得自己写）
'''

from __future__ import division

import sys,os
import ujson,json
import traceback
from collections import OrderedDict
from datetime import datetime, time, timedelta
from copy import copy

from vnpy.event import Event
from vnpy.trader.vtEvent import *
from vnpy.trader.vtConstant import *
from vnpy.trader.vtObject import VtTickData, VtBarData
from vnpy.trader.vtGateway import VtSubscribeReq, VtOrderReq, VtCancelOrderReq, VtLogData
from vnpy.trader import vtFunction
from vnpy.trader import hicloud

from .ctaBase import *
from .strategy import STRATEGY_CLASS

## william
from vnpy.trader.vtGlobal import globalSetting
from logging import INFO, ERROR

## 发送邮件通知
import codecs
import inspect

########################################################################
cdef class CtaEngine(object):
    """CTA策略引擎"""

    cdef dict __dict__
    cdef public:
        str accountID, dateBase, settingFileName
        str tradingDay, lastTradingDay
        set STATUS_FINISHED
        int sendMailCounter, exitCounter
        dict strategyDict, positionInfo
        list accountContracts, lastTickFileds
        dict tickStrategyDict, lastTickDict, lastBarDict
        set tradeSet
        list subscribeContracts

    ## ---------------------------------------------------------------------
    if not hasattr(sys.modules[__name__], '__file__'):
        __file__ = inspect.getfile(inspect.currentframe())
    ## ---------------------------------------------------------------------

    #----------------------------------------------------------------------
    def __cinit__(self, mainEngine, eventEngine):
        """Constructor"""
        self.mainEngine  = mainEngine
        self.eventEngine = eventEngine        
        self.accountName = globalSetting.accountName

        self.accountID   = globalSetting.accountID
        self.dataBase    = self.accountID
        self.STATUS_FINISHED = set([STATUS_REJECTED, STATUS_CANCELLED, STATUS_ALLTRADED])

        self.settingFileName = 'CTA_setting.json'
        self.settingfilePath = vtFunction.getJsonPath(self.settingFileName, __file__)
        ## ---------------------------------------------------------------------

        ## =====================================================================
        ## william
        ## 有关日期的设置
        ## date: 指的是日期, 即 python 里面的 date() 格式, eg: 2017-01-01
        ## day:  是 date 转变过来的字符串格式, eg:'20170101'
        ## ---------------------------------------------------------------------
        ## 期货交易日历表
        ## Usage: mainEngine.ctaEngine.ChinaFuturesCalendar
        ## __格式是 date, 即 2017-01-01, 需要用 date 格式来匹配__
        ## nights: 夜盘日期,
        ## days:   日盘日期,
        self.ChinaFuturesCalendar = vtFunction.dbMySQLQuery('dev', 
            """select * from ChinaFuturesCalendar where days >= 20170101;""")
        ## =====================================================================

        # 当前日期
        self.tradingDay = vtFunction.tradingDay()
        self.tradingDate = vtFunction.tradingDate()
        self.lastTradingDay = vtFunction.lastTradingDay()
        self.lastTradingDate = vtFunction.lastTradingDate()

        ## 交易所连续交易时间
        self.exchangeTradingContinuous = False
        ## ----------------------------------------
        ## 交易所开盘状态确定
        self.exchangeTradingStatus = {
            'DCE'  : False,
            'SHFE' : False,
            'CZCE' : False,
            'INE'  : False}
        ## ----------------------------------------

        self.sendMailTime = datetime.now()
        self.sendMailStatus = False
        self.sendMailContent = ''
        self.sendMailCounter = 0

        # 保存策略实例的字典
        # key为策略名称，value为策略实例，注意策略名称不允许重复
        self.strategyDict = {}
        
        ## 持仓信息
        ## ------
        self.positionInfo = {}
        ## 持仓合约
        ## -------
        self.accountContracts = []

        ## =====================================================================
        ## CTA 策略相关的 Dict
        ## ---------------------------------------------------------------------
        # 保存vtSymbol和策略实例映射的字典（用于推送tick数据）
        # 由于可能多个strategy交易同一个vtSymbol，因此key为vtSymbol
        # value为包含所有相关strategy对象的list
        self.tickStrategyDict  = {}
        self.lastTickDict      = {}
        self.lastTickFileds    = ['vtSymbol', 'datetime', 'lastPrice',
                                  'volume', 'turnover',
                                  'openPrice', 'highestPrice', 'lowestPrice',
                                  'bidPrice1', 'askPrice1',
                                  'bidVolume1', 'askVolume1',
                                  'upperLimit','lowerLimit','exchange']
        self.lastBarDict       = {}
        ## ---------------------------------------------------------------------
        ## 提取 lastTick
        try:
            df = vtFunction.fetchMySQL(db = self.dataBase, 
                query = 'select * from lastTickInfo where TradingDay = %s' %self.tradingDay)
            if len(df):
                df.rename(columns = {'updateTime':'datetime'}, inplace = True)
                for i in xrange(len(df)):
                    self.lastTickDict[df.at[i, 'vtSymbol']] = dict(df.ix[i])
        except:
            self.writeCtaLog(u'没有 lastTickInfo 数据')
        ## ---------------------------------------------------------------------

        # 保存vtOrderID和strategy对象映射的字典（用于推送order和trade数据）
        # key   为 vtOrderID，
        # value 为 strategy对象
        self.orderStrategyDict = {}     
        
        # 保存策略名称和委托号列表的字典
        # key   为 name，
        # value 为保存 orderID（限价+本地停止）的集合
        self.strategyOrderDict = {}

        # 本地停止单编号计数
        self.stopOrderCount = 0
        # stopOrderID = STOPORDERPREFIX + str(stopOrderCount)
        
        # 本地停止单字典
        # key为stopOrderID，value为stopOrder对象
        self.stopOrderDict = {}             # 停止单撤销后不会从本字典中删除
        self.workingStopOrderDict = {}      # 停止单撤销后会从本字典中删除

        # 成交号集合，用来过滤已经收到过的成交推送
        self.tradeSet = set()
        
        ## =====================================================================
        ## william
        ## 有关订阅合约行情
        ## ---------------------------------------------------------------------
        ## 所有的主力合约
        self.mainContracts = vtFunction.dbMySQLQuery(
            'china_futures_bar',
            """
            select * 
            from main_contract_daily 
            where TradingDay = %s 
            """ %self.lastTradingDay).Main_contract.values
        ## ----------------------------------------------------------------------
        ## william
        ## 需要订阅的合约
        self.subscribeContracts = []
        for dbName in [globalSetting.accountID]:
            for tbName in ['positionInfo','failedInfo','tradingSignal']:
                try:
                    temp = self.fetchInstrumentID(dbName, tbName)
                    self.subscribeContracts = list(set(self.subscribeContracts) | 
                                                   set(temp))
                except:
                    None
        ## ---------------------------------------------------------------------
        self.allContracts = list(set(self.subscribeContracts) | 
                                 set(self.mainContracts))
        self.allContracts = self.subscribeContracts
        self.tickInfo = {}
        ## =====================================================================
        ## 记录合约相关的 
        ## 1. priceTick
        ## 2. size
        ## ---------------------------------------------------------------------
        for x in self.allContracts:
            try:
                self.tickInfo[x] = {k:self.mainEngine.getContract(x).__dict__[k] 
                                    for k in ['vtSymbol','priceTick','size']}
            except:
                None
        ## =====================================================================

        ## =====================================================================
        self.DAY_START   = time(8, 00)       # 日盘启动和停止时间
        self.DAY_END     = time(15, 15)
        
        self.NIGHT_START = time(20, 00)      # 夜盘启动和停止时间
        self.NIGHT_END   = time(2, 30)
        self.exitCounter = 0
        ## =====================================================================

        # 引擎类型为实盘
        self.engineType = ENGINETYPE_TRADING
        
        # 注册日式事件类型
        self.mainEngine.registerLogEvent(EVENT_CTA_LOG)
        
        # 注册事件监听
        self.registerEvent()
 
    #----------------------------------------------------------------------
    cpdef sendOrder(self, str vtSymbol, orderType, price, int volume, strategy):
        """发单"""
        ## =====================================================================
        ## william
        ## 这里的 strategy 来自具体的策略
        ## Ref: /stragegy/strategyBBminute.py
        contract = self.mainEngine.getContract(vtSymbol)
        ## =====================================================================
        
        req = VtOrderReq()
        req.symbol = contract.symbol
        req.exchange = contract.exchange
        req.vtSymbol = contract.vtSymbol
        ########################################################################
        ## william
        ## 这个需要参考最小价格变动单位：　priceTick
        req.price  = self.roundToPriceTick(contract.priceTick, price)
        req.volume = volume
        
        req.productClass = strategy.productClass
        req.currency = strategy.currency        
        
        ########################################################################
        ## william
        ## Ref: /vn.trader/language/chinese/constant.py/
        # 设计为CTA引擎发出的委托只允许使用限价单
        req.priceType = PRICETYPE_LIMITPRICE    
        
        # CTA委托类型映射
        if orderType == CTAORDER_BUY:
            req.direction = DIRECTION_LONG
            req.offset = OFFSET_OPEN
        elif orderType == CTAORDER_SELL:
            req.direction = DIRECTION_SHORT
            req.offset = OFFSET_CLOSE
        elif orderType == CTAORDER_SHORT:
            req.direction = DIRECTION_SHORT
            req.offset = OFFSET_OPEN
        elif orderType == CTAORDER_COVER:
            req.direction = DIRECTION_LONG
            req.offset = OFFSET_CLOSE
            
        # 委托转换
        reqList = self.mainEngine.convertOrderReq(req)
        cdef list vtOrderIDList = []
        
        if not reqList:
            return vtOrderIDList
        
        for convertedReq in reqList:
            # 发单
            vtOrderID = self.mainEngine.sendOrder(convertedReq, contract.gatewayName)    
            # 保存vtOrderID和策略的映射关系
            self.orderStrategyDict[vtOrderID] = strategy
            # 添加到策略委托号集合中                                 
            self.strategyOrderDict[strategy.name].add(vtOrderID)                         
            vtOrderIDList.append(vtOrderID)
            
        self.writeCtaLog(u'策略%s发送委托: %s, %s, %s, %s@%s\n' 
                         %(strategy.name, vtSymbol, req.direction, req.offset, volume, req.price))
        return vtOrderIDList

    
    #----------------------------------------------------------------------
    cpdef cancelOrder(self, str vtOrderID):
        """撤单"""
        # 查询报单对象
        order = self.mainEngine.getOrder(vtOrderID)
        
        # 如果查询成功
        if order:
            # 检查是否报单还有效，只有有效时才发出撤单指令
            orderFinished = (order.status == STATUS_ALLTRADED or 
                             order.status == STATUS_CANCELLED)
            if not orderFinished:
                req = VtCancelOrderReq()
                req.symbol    = order.symbol
                req.exchange  = order.exchange
                req.frontID   = order.frontID
                req.sessionID = order.sessionID
                req.orderID   = order.orderID
                self.mainEngine.cancelOrder(req, order.gatewayName)    
            else:
                if order.status == STATUS_ALLTRADED:
                    self.writeCtaLog(u'委托单({0}已执行，无法撤销'.format(vtOrderID))
                if order.status == STATUS_CANCELLED:
                    self.writeCtaLog(u'委托单({0}已撤销，无法再次撤销'.format(vtOrderID))


    #----------------------------------------------------------------------
    cpdef sendStopOrder(self, str vtSymbol, orderType, price, int volume, strategy):
        """发停止单（本地实现）"""
        self.stopOrderCount += 1
        stopOrderID = STOPORDERPREFIX + str(self.stopOrderCount)
        
        so             = StopOrder()
        so.vtSymbol    = vtSymbol
        so.orderType   = orderType
        so.price       = price
        so.volume      = volume
        so.strategy    = strategy
        so.stopOrderID = stopOrderID
        so.status      = STOPORDER_WAITING
        
        if orderType == CTAORDER_BUY:
            so.direction = DIRECTION_LONG
            so.offset    = OFFSET_OPEN
        elif orderType == CTAORDER_SELL:
            so.direction = DIRECTION_SHORT
            so.offset    = OFFSET_CLOSE
        elif orderType == CTAORDER_SHORT:
            so.direction = DIRECTION_SHORT
            so.offset    = OFFSET_OPEN
        elif orderType == CTAORDER_COVER:
            so.direction = DIRECTION_LONG
            so.offset    = OFFSET_CLOSE           
        
        # 保存stopOrder对象到字典中
        self.stopOrderDict[stopOrderID] = so
        self.workingStopOrderDict[stopOrderID] = so
        
        # 保存stopOrderID到策略委托号集合中
        self.strategyOrderDict[strategy.name].add(stopOrderID)
        
        # 推送停止单状态
        strategy.onStopOrder(so)
        
        return [stopOrderID]
    
    #----------------------------------------------------------------------
    cpdef cancelStopOrder(self, str stopOrderID):
        """撤销停止单"""
        # 检查停止单是否存在
        if stopOrderID in self.workingStopOrderDict:
            so = self.workingStopOrderDict[stopOrderID]
            strategy = so.strategy
            
            # 更改停止单状态为已撤销
            so.status = STOPORDER_CANCELLED
            
            # 从活动停止单字典中移除
            del self.workingStopOrderDict[stopOrderID]
            
            # 从策略委托号集合中移除
            s = self.strategyOrderDict[strategy.name]
            if stopOrderID in s:
                s.remove(stopOrderID)
            
            # 通知策略
            strategy.onStopOrder(so)

    #----------------------------------------------------------------------
    cpdef processStopOrder(self, tick):
        """收到行情后处理本地停止单（检查是否要立即发出）"""
        cdef str vtSymbol = tick.vtSymbol
        
        # 首先检查是否有策略交易该合约
        if vtSymbol in self.tickStrategyDict:
            # 遍历等待中的停止单，检查是否会被触发
            for so in self.workingStopOrderDict.values():
                if so.vtSymbol == vtSymbol:
                    longTriggered = so.direction == DIRECTION_LONG and tick.lastPrice>=so.price        # 多头停止单被触发
                    shortTriggered = so.direction == DIRECTION_SHORT and tick.lastPrice<=so.price     # 空头停止单被触发
                    
                    if longTriggered or shortTriggered:
                        # 买入和卖出分别以涨停跌停价发单（模拟市价单）
                        if so.direction == DIRECTION_LONG:
                            price = tick.upperLimit
                        else:
                            price = tick.lowerLimit
                        
                        # 发出市价委托
                        self.sendOrder(so.vtSymbol, so.orderType, price, so.volume, so.strategy)
                        
                        # 从活动停止单字典中移除该停止单
                        del self.workingStopOrderDict[so.stopOrderID]
                        
                        # 从策略委托号集合中移除
                        s = self.strategyOrderDict[so.strategy.name]
                        if so.stopOrderID in s:
                            s.remove(so.stopOrderID)
                        
                        # 更新停止单状态，并通知策略
                        so.status = STOPORDER_TRIGGERED
                        so.strategy.onStopOrder(so)

    #----------------------------------------------------------------------
    cpdef processTickEvent(self, event):
        """处理行情推送"""
        tick = event.dict_['data']
        ## ---------------------------------------------------------------------
        # 收到tick行情后，先处理本地停止单（检查是否要立即发出）
        # self.processStopOrder(tick)
        ## ---------------------------------------------------------------------
        ## 判断交易所是不是已经开盘了
        if (self.exchangeTradingContinuous and 
            not self.exchangeTradingStatus[tick.exchange]):
            if ( (datetime.now().hour in [8,9] and tick.time >= "09:00:00") or
                 (datetime.now().hour in [20,21] and tick.time >= "21:00:00") or 
                 datetime.now().hour not in [8,9,20,21]):
                self.exchangeTradingStatus[tick.exchange] = True
        ## ---------------------------------------------------------------------
        # tick时间可能出现异常数据，使用try...except实现捕捉和过滤
        try:
            # 添加datetime字段
            if not tick.datetime:
                tick.datetime = datetime.strptime(' '.join(
                                [tick.date, tick.time]), '%Y%m%d %H:%M:%S.%f')
        except ValueError:
            self.writeCtaLog(traceback.format_exc())
            return
        ## ---------------------------------------------------------------------

        ## ---------------------------------------------------------------------
        # 推送tick到对应的策略实例进行处理
        if tick.vtSymbol in self.tickStrategyDict:
            ## -----------------------------------------------------------------
            # 逐个推送到策略实例中
            l = self.tickStrategyDict[tick.vtSymbol]
            for strategy in l:
                self.callStrategyFunc(strategy, strategy.onTick, tick)
                ## =============================================================
                ## william
                ## 把 TickData 数据推送到策略函数里面
                # self.callStrategyFunc(strategy, strategy.onClosePosition, ctaTick)
                ## =============================================================
            ## -----------------------------------------------------------------
        ## ---------------------------------------------------------------------

        ## ---------------------------------------------------------------------
        if tick.vtSymbol in self.allContracts:
            ## -------------------------------------------------------------------------------------
            if tick.vtSymbol in self.lastTickDict.keys():
                tick.highestPrice = max(tick.highestPrice, 
                                        self.lastTickDict[tick.vtSymbol]['highestPrice'])
                tick.lowestPrice = min(tick.lowestPrice, 
                                       self.lastTickDict[tick.vtSymbol]['lowestPrice'])
            ## -------------------------------------------------------------------------------------
            self.lastTickDict[tick.vtSymbol] = {k:tick.__dict__[k] for k in self.lastTickFileds}
        ## ---------------------------------------------------------------------

    #----------------------------------------------------------------------
    cpdef processOrderEvent(self, event):
        """处理委托推送"""
        order = event.dict_['data']
        
        cdef str vtOrderID = order.vtOrderID
        
        if vtOrderID in self.orderStrategyDict:
            strategy = self.orderStrategyDict[vtOrderID]            

            ## =================================================================            
            ## william
            ## 非全平仓才推送 OnOrder
            ## 全平仓不需要推送
            if strategy.name != 'CLOSE_ALL':
                ## -------------------------------------------------------------
                # 如果委托已经完成（拒单、撤销、全成），则从活动委托集合中移除
                if order.status in self.STATUS_FINISHED:
                    s = self.strategyOrderDict[strategy.name]
                    if vtOrderID in s:
                        s.remove(vtOrderID)
                ## -------------------------------------------------------------
                self.callStrategyFunc(strategy, strategy.onOrder, order)
    
    #----------------------------------------------------------------------
    cpdef processTradeEvent(self, event):
        """处理成交推送"""
        trade = event.dict_['data']
        
        # 过滤已经收到过的成交回报
        if trade.vtTradeID in self.tradeSet:
            return
        self.tradeSet.add(trade.vtTradeID)
        
        # 将成交推送到策略对象中
        if trade.vtOrderID in self.orderStrategyDict:
            strategy = self.orderStrategyDict[trade.vtOrderID]
            
            ## =================================================================            
            ## william
            ## 非全平仓才推送 OnOrder
            ## 全平仓不需要推送
            if strategy.name != 'CLOSE_ALL':
                # 计算策略持仓
                if trade.direction == DIRECTION_LONG:
                    strategy.pos += trade.volume
                else:
                    strategy.pos -= trade.volume
                self.callStrategyFunc(strategy, strategy.onTrade, trade)
            else:
                pass

            ## =================================================================
    

    ############################################################################
    ## william
    ## 更新状态，需要订阅
    ############################################################################
    cpdef processTradingStatus(self, event):
        """控制交易开始与停止状态"""
        cdef:
            int h = datetime.now().hour
            int m = datetime.now().minute
            int s = datetime.now().second
        ## =====================================================================
        ## 启动尾盘交易
        ## =====================================================================
        if ( (h in [8,20] and m == 59 and s >= 58) or 
             (h in [21,22,23,0,1,2]) or 
             (9 <= h <= 15) ):
            self.exchangeTradingContinuous = True
        else:
            self.exchangeTradingContinuous = False
        ## =====================================================================

        if (m % 5 != 0 or s % 20 != 0):
            return 
        ## ------------------------

        ## ---------------------------------------------------------------------
        if ((h == self.NIGHT_END.hour and m >= self.NIGHT_END.minute) or 
            (h == self.DAY_END.hour and m >= self.DAY_END.minute)):
            self.exitCounter += 1
            self.writeCtaLog(u'即将退出系统，计数器：%s' %self.exitCounter)
            if self.exitCounter >= 3:
                os._exit(0)
        ## ---------------------------------------------------------------------


    #----------------------------------------------------------------------
    cpdef registerEvent(self):
        """注册事件监听"""
        self.eventEngine.register(EVENT_TICK, self.processTickEvent)
        self.eventEngine.register(EVENT_ORDER, self.processOrderEvent)
        self.eventEngine.register(EVENT_TRADE, self.processTradeEvent)
        self.eventEngine.register(EVENT_TIMER, self.processTradingStatus)
    
    #----------------------------------------------------------------------
    cpdef loadTick(self):
        """从数据库中读取Tick数据，startDate是datetime对象"""
        pass

    #----------------------------------------------------------------------
    cpdef loadBar(self):
        """从数据库中读取Bar数据，startDate是datetime对象"""
        pass
    
    #----------------------------------------------------------------------
    cpdef writeCtaLog(self, content, int logLevel = INFO, str gatewayName = 'CTA'):
        """快速发出CTA模块日志事件"""
        log = VtLogData()
        log.logContent = content
        log.gatewayName = gatewayName    ## 'CTA_STRATEGY'
        log.logLevel = logLevel
        event = Event(type_=EVENT_CTA_LOG)
        event.dict_['data'] = log
        self.eventEngine.put(event)   
    
    #----------------------------------------------------------------------
    cpdef loadStrategy(self, setting):
        """载入策略"""
        try:
            name = setting['name']
            className = setting['className']
        except Exception:
            msg = traceback.format_exc()
            self.writeCtaLog(u'载入策略出错：%s' %msg)
            return
        
        # 获取策略类
        strategyClass = STRATEGY_CLASS.get(className, None)
        if not strategyClass:
            self.writeCtaLog(u'找不到策略类：%s' %className)
            return
        
        # 防止策略重名
        if name in self.strategyDict:
            self.writeCtaLog(u'策略实例重名：%s' %name)
        else:
            # 创建策略实例
            strategy = strategyClass(self, setting)  
            self.strategyDict[name] = strategy

            # 创建委托号列表
            self.strategyOrderDict[name] = set()
            
            ####################################################################
            ## william
            # 保存Tick映射关系
            if 'vtSymbol' in setting.keys() and len(setting['vtSymbol']) != 0:
                vtSymbolSet   = setting['vtSymbol'].replace(" ", "")
                vtSymbolStrat = vtSymbolSet.split(',')
                vtSymbolList  = list(set(self.subscribeContracts) | set(vtSymbolStrat))
            else:
                vtSymbolList  = self.subscribeContracts

            for vtSymbol in vtSymbolList:
                if vtSymbol in self.tickStrategyDict:
                    ############################################################
                    ## william
                    l = self.tickStrategyDict[vtSymbol]
                else:
                    l = []
                    ############################################################
                    ## william
                    self.tickStrategyDict[vtSymbol] = l
                l.append(strategy)

                # 订阅合约
                ################################################################
                ## william
                contract = self.mainEngine.getContract(vtSymbol)
                if contract:
                    req          = VtSubscribeReq()
                    req.symbol   = contract.symbol
                    req.exchange = contract.exchange
                    # 对于IB接口订阅行情时所需的货币和产品类型，从策略属性中获取
                    # req.currency = strategy.currency
                    # req.productClass = strategy.productClass
                    ############################################################
                    ## william
                    self.mainEngine.subscribe(req, contract.gatewayName)
                    ############################################################
                else:
                    self.writeCtaLog(u'%s的交易合约%s无法找到' %(name, vtSymbol))

    #----------------------------------------------------------------------
    cpdef initStrategy(self, name):
        """初始化策略"""
        if name in self.strategyDict:
            strategy = self.strategyDict[name]
            
            if not strategy.inited:
                strategy.inited = True
                self.callStrategyFunc(strategy, strategy.onInit)
            else:
                self.writeCtaLog(u'请勿重复初始化策略实例：%s' %name)
        else:
            self.writeCtaLog(u'策略实例不存在：%s' %name)        

    #---------------------------------------------------------------------
    cpdef startStrategy(self, name):
        """启动策略"""
        ## ---------------------------------------------------------------------
        ## 1.判断策略名称是否存在字典中
        if name in self.strategyDict:
            ## -----------------------------------------------------------------
            ## 2.提取策略
            strategy = self.strategyDict[name]
            ## -----------------------------------------------------------------
            ## 3.判断策略是否运行
            if strategy.inited and not strategy.trading:
                ## -----------------------------------------------------------------
                ## 4.设置运行状态
                strategy.trading = True
                ## -----------------------------------------------------------------
                ## 5.启动策略
                self.callStrategyFunc(strategy, strategy.onStart)
        else:
            self.writeCtaLog(u'策略实例不存在：%s' %name)
    
    #----------------------------------------------------------------------
    cpdef stopStrategy(self, name):
        """停止策略"""
        ## ---------------------------------------------------------------------
        ## 1.判断策略名称是否存在字典中
        if name in self.strategyDict:
            ## -----------------------------------------------------------------
            ## 2.提取策略
            strategy = self.strategyDict[name]
            ## -----------------------------------------------------------------
            ## 3.停止交易
            if strategy.trading:
                ## -------------------------------------------------------------
                ## 4.设置交易状态为False
                strategy.trading = False
                ## -------------------------------------------------------------
                ## 5.调用策略的停止方法, onStop
                self.callStrategyFunc(strategy, strategy.onStop)
                ## -------------------------------------------------------------
                ## 6.对该策略发出的所有限价单进行撤单
                for vtOrderID, s in self.orderStrategyDict.items():
                    if s is strategy:
                        self.cancelOrder(vtOrderID)
                ## -------------------------------------------------------------
                ## 7.对该策略发出的所有本地停止单撤单
                for stopOrderID, so in self.workingStopOrderDict.items():
                    if so.strategy is strategy:
                        self.cancelStopOrder(stopOrderID)
        else:
            self.writeCtaLog(u'策略实例不存在：%s' %name)    
            
    #----------------------------------------------------------------------
    cpdef initAll(self):
        """全部初始化"""
        for name in self.strategyDict.keys():
            self.initStrategy(name)    
            
    #----------------------------------------------------------------------
    cpdef startAll(self):
        """全部启动"""
        for name in self.strategyDict.keys():
            self.startStrategy(name)
            
    #----------------------------------------------------------------------
    cpdef stopAll(self):
        """全部停止"""
        for name in self.strategyDict.keys():
            self.stopStrategy(name)    
    
    #----------------------------------------------------------------------
    cpdef saveSetting(self):
        """保存策略配置"""
        with open(self.settingfilePath, 'w') as f:
            l = []
            
            for strategy in self.strategyDict.values():
                setting = {}
                for param in strategy.paramList:
                    setting[param] = strategy.__getattribute__(param)
                l.append(setting)
            
            jsonL = ujson.dumps(l, indent=4)
            f.write(jsonL)
    
    #----------------------------------------------------------------------
    cpdef loadSetting(self):
        """读取策略配置"""
        with open(self.settingfilePath) as f:
            l = json.load(f)
            
            for setting in l:
                self.loadStrategy(setting)
    
    #----------------------------------------------------------------------
    cpdef getStrategyVar(self, name):
        """获取策略当前的变量字典"""
        if name in self.strategyDict:
            strategy = self.strategyDict[name]
            varDict = OrderedDict()
            
            for key in strategy.varList:
                varDict[key] = strategy.__getattribute__(key)
            
            return varDict
        else:
            self.writeCtaLog(u'策略实例不存在：' + name)    
            return None
    
    #----------------------------------------------------------------------
    cpdef getStrategyParam(self, name):
        """获取策略的参数字典"""
        if name in self.strategyDict:
            strategy = self.strategyDict[name]
            paramDict = OrderedDict()
            
            for key in strategy.paramList:  
                paramDict[key] = strategy.__getattribute__(key)
            
            return paramDict
        else:
            self.writeCtaLog(u'策略实例不存在：' + name)    
            return None
        
    #----------------------------------------------------------------------
    cpdef putStrategyEvent(self, name):
        """触发策略状态变化事件（通常用于通知GUI更新）"""
        event = Event(EVENT_CTA_STRATEGY+name)
        self.eventEngine.put(event)
        
    #----------------------------------------------------------------------
    cpdef callStrategyFunc(self, strategy, func, params=None):
        """调用策略的函数，若触发异常则捕捉"""
        try:
            if params:
                func(params)
            else:
                func()
        except Exception:
            # 停止策略，修改状态为未初始化
            strategy.trading = False
            strategy.inited = False
            
            # 发出日志
            content = '\n'.join([u'策略%s触发异常已停止' %strategy.name,
                                traceback.format_exc()])
            ## -----------------------------
            self.sendMailContent += content

            if not self.sendMailStatus:
                self.sendMailStatus = True
                hicloud.sendMail(
                    self.accountName,
                    self.sendMailContent,
                    'ERROR')
                self.sendMailTime = datetime.now()
            elif ((datetime.now() - self.sendMailTime).seconds > 60 and 
                  (self.sendMailCounter < 10)):
                hicloud.sendMail(
                    self.accountName,
                    self.sendMailContent,
                    'ERROR')
                self.sendMailTime = datetime.now()
                self.sendMailContent = ''
                self.sendMailCounter += 1
                
            ## -----------------------------
            self.writeCtaLog(content)
            
    ## =========================================================================
    ## william
    ## 原来的设置是写入　mongoDB
    ## 这里需要修改
    ## =========================================================================
    #----------------------------------------------------------------------
    cpdef saveSyncData(self, strategy):
        """保存策略的持仓情况到数据库"""
        pass
    
    #----------------------------------------------------------------------
    cpdef loadSyncData(self):
        """从数据库载入策略的持仓情况"""
        pass
                
    #----------------------------------------------------------------------
    cpdef roundToPriceTick(self, priceTick, price):
        """取整价格到合约最小价格变动"""
        if not priceTick:
            return price
        return round(price/priceTick, 0) * priceTick  
    
    #----------------------------------------------------------------------
    cpdef stop(self):
        """停止"""
        pass
    
    #----------------------------------------------------------------------
    cpdef cancelAll(self, name):
        """全部撤单"""
        s = self.strategyOrderDict[name]
        
        # 遍历列表，全部撤单
        # 这里不能直接遍历集合s，因为撤单时会修改s中的内容，导致出错
        for orderID in list(s):
            if STOPORDERPREFIX in orderID:
                self.cancelStopOrder(orderID)
            else:
                self.cancelOrder(orderID)

    ############################################################################
    ## 获取基金的 InstrumentID
    ############################################################################
    cpdef fetchInstrumentID(self, str dbName, str tbName):
        temp = vtFunction.dbMySQLQuery(dbName,
            """
            select * from %s
            """ %(tbName))
        return(temp.InstrumentID.values)
