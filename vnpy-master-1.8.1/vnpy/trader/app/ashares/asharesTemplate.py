# encoding: UTF-8

'''
本文件包含了 ASHARES 引擎中的策略开发用模板，开发策略时需要继承 ASharesTemplate类。
'''
from __future__ import division
import os,sys,subprocess
import numpy as np
import talib

from vnpy.trader.vtConstant import *
from vnpy.trader.vtObject import VtBarData
from vnpy.trader import vtFunction

from .asharesBase import *

from datetime import datetime,time,timedelta
from math import ceil
from random import randint

## -----------------------------------------------------------------------------
reload(sys) # Python2.5 初始化后会删除 sys.setdefaultencoding 这个方法，我们需要重新载入   
sys.setdefaultencoding('utf-8')   
from vnpy.trader.vtGlobal import globalSetting
## -----------------------------------------------------------------------------


########################################################################
class ASharesTemplate(object):
    """CTA策略模板"""
    
    # 策略类的名称和作者
    name = ""
    className = "ASharesTemplate"
    author = EMPTY_UNICODE
    strategyID = 'testing'
    
    # 策略的基本参数
    name = EMPTY_UNICODE           # 策略实例名称
    vtSymbol = EMPTY_STRING        # 交易的合约vt系统代码    
    productClass = EMPTY_STRING    # 产品类型（只有IB接口需要）
    currency = EMPTY_STRING        # 货币（只有IB接口需要）
    
    # 参数列表，保存了参数的名称
    paramList = ['name',
                 'className',
                 'author',
                 'vtSymbol']
    
    # 变量列表，保存了变量的名称
    varList = ['inited',
               'trading',
               'pos']
    
    # 同步列表，保存了需要保存到数据库的变量名称
    syncList = ['pos']

    ## -------------------------------------------------------------------------
    ## 各种控制条件
    ## 策略的基本变量，由引擎管理
    inited         = False                    # 是否进行了初始化
    trading        = False                    # 是否启动交易，由引擎管理
    tradingBeginning = False                    # 开盘启动交易
    tradingSplit = False                    # 开盘拆单交易
    tradingBetween = False                    # 尾盘的拆单平仓交易
    tradingEnding = False                    # 收盘开启交易
    pos            = 0                        # 持仓情况
    sendMailStatus = False                    # 是否已经发送邮件
    timer = {}                # 计时器, 用于记录单个合约发单的间隔时间
    ## -------------------------------------------------------------------------

    ## -------------------------------------------------------------------------
    tradedOrder = {}        # 当日订单完成的情况
    tradedOrderBeginning = {}        # 当日开盘完成的已订单
    tradedOrderEnding = {}        # 当日收盘完成的已订单
    tradedOrderFailedInfo = {}        # 昨天未成交订单的已交易订单
    ## -------------------------------------------------------------------------

    ## -------------------------------------------------------------------------
    ## 各种交易订单的合成
    ## -------------------------------------------------------------------------
    vtOrderIDList = []        # 保存委托代码的列表
    vtOrderIDListBeginning = []        # 开盘的订单
    vtOrderIDListSplit = []       # 开盘的拆单
    vtOrderIDListBetween = []
    vtOrderIDListEnding = []        # 收盘的订单
    vtOrderIDListFailedInfo = []        # 失败的合约订单存储
    ## -------------------------------------------------------------------------

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


    ## =========================================================================
    def __init__(self, asharesEngine, setting):
        """Constructor"""
        self.asharesEngine = asharesEngine

        ## ---------------------------------
        ## 设置策略的参数
        if setting:
            d = self.__dict__
            for key in self.paramList:
                if key in setting:
                    d[key] = setting[key]
        ## ---------------------------------

        ## =====================================================================
        ## 交易时点
        self.tradingDay = self.asharesEngine.tradingDay
        self.lastTradingDay = self.asharesEngine.lastTradingDay
        self.tradingDate = self.asharesEngine.tradingDate
        self.lastTradingDate = self.asharesEngine.lastTradingDate

        self.tradingStartCounter = 0

        ## 
        self.tradingOpenHour = [9]
        self.tradingOpenMinute1 = 0
        self.tradingOpenMinute2 = 10
        ## 
        self.tradingCloseHour = 14
        self.tradingCloseMinute1 = 50
        self.tradingCloseMinute2 = 59

        self.accountID = globalSetting.accountID
        self.randomNo = 50 + randint(-5,5)    ## 随机间隔多少秒再下单
        ## =====================================================================


    #----------------------------------------------------------------------
    def onInit(self):
        """初始化策略（必须由用户继承实现）"""
        raise NotImplementedError
    
    #----------------------------------------------------------------------
    def onStart(self):
        """启动策略（必须由用户继承实现）"""
        raise NotImplementedError
    
    #----------------------------------------------------------------------
    def onStop(self):
        """停止策略（必须由用户继承实现）"""
        raise NotImplementedError

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
    def buy(self, vtSymbol, price, volume):
        """股票买入"""
        return self.sendOrder(vtSymbol, ASHARES_BUY, price, volume)
    
    #----------------------------------------------------------------------
    def sell(self, vtSymbol, price, volume):
        """股票卖出"""
        return self.sendOrder(vtSymbol, ASHARES_SELL, price, volume)       
        
    #----------------------------------------------------------------------
    def sendOrder(self, vtSymbol, orderType, price, volume):
        """发送委托"""
        if self.trading:
            return self.asharesEngine.sendOrder(vtSymbol, orderType, price, volume, self)
        else:
            # 交易停止时发单返回空字符串
            self.writeASharesLog(u'交易状态已停止')
            return []
        
    #----------------------------------------------------------------------
    def cancelOrder(self, vtOrderID):
        """撤单"""
        # 如果发单号为空字符串，则不进行后续操作
        if not vtOrderID:
            return
        self.asharesEngine.cancelOrder(vtOrderID)

    #----------------------------------------------------------------------
    def cancelAll(self):
        """全部撤单"""
        self.asharesEngine.cancelAll(self.name)
    
    #----------------------------------------------------------------------
    def loadTick(self, days):
        """读取tick数据"""
        pass

    #----------------------------------------------------------------------
    def loadBar(self, days):
        """读取bar数据"""
        pass

    #----------------------------------------------------------------------
    def writeASharesLog(self, content):
        """记录CTA日志"""
        content = self.name + ':' + content
        self.asharesEngine.writeASharesLog(content)
        
    #----------------------------------------------------------------------
    def putEvent(self):
        """发出策略状态变化事件"""
        self.asharesEngine.putStrategyEvent(self.name)
        
    #----------------------------------------------------------------------
    def getEngineType(self):
        """查询当前运行的环境"""
        return self.asharesEngine.engineType
    
    #----------------------------------------------------------------------
    def saveSyncData(self):
        """保存同步数据到数据库"""
        if self.trading:
            self.asharesEngine.saveSyncData(self)
    
    #----------------------------------------------------------------------
    def getPriceTick(self, vtSymbol):
        """查询最小价格变动"""
        return self.asharesEngine.getPriceTick(vtSymbol)

    #----------------------------------------------------------------------
    def getTick(self, vtSymbol):
        """查询最小价格变动"""
        return self.asharesEngine.getTick(vtSymbol)

    #----------------------------------------------------------------------
    def getAllOrdersDataFrame(self):
        """查询所有委托"""
        return self.asharesEngine.mainEngine.getAllOrdersDataFrame()


    ############################################################################
    ## william
    ## 限制价格在 UpperLimit 和 LowerLimit 之间
    ############################################################################
    def priceBetweenUpperLower(self, price, vtSymbol):
        ## -----------------------------------------------------------
        s = self.getPriceTick(vtSymbol)
        tick = self.getTick(vtSymbol)
        
        u = tick.upperLimit - s
        l = tick.lowerLimit + s
        return min(max(l, price), u)

    ############################################################################
    ## william
    ## 现在买入的股票手数为 100 的倍数
    ############################################################################
    def roundToLot(self, volume):
        """合并到手=100股票"""
        return int(ceil(volume/100.0)) * 100


    def sendTradingOrder(self,
                         tradingOrder, 
                         orderDict, 
                         orderIDList, 
                         priceType, 
                         price = None, 
                         volume = 0, 
                         addTick = 0, 
                         discount = 0.0):
        ## 股票代码
        ticker = orderDict["vtSymbol"].encode('ascii','ignore')
        tempPriceTick = self.getPriceTick(ticker)
        tempDirection = orderDict['direction']

        ## tick data
        tick = self.getTick(ticker)

        if priceType == 'last':
            tempBestPrice = tick.lastPrice
        elif priceType == 'best':
            if tempDirection == 'buy':
                tempBestPrice = tick.askPrice1
            elif tempDirection == 'sell':
                tempBestPrice = tick.bidPrice1
        elif priceType == 'chasing':
            if tempDirection == 'buy':
                tempBestPrice = tick.bidPrice1
            elif tempDirection == 'sell':
                tempBestPrice = tick.askPrice1
        elif priceType == "limit":  ## 指定价格下单
            if price:
                tempBestPrice = price
            else:
                print u'错误的价格输入'
                return None

        ## =====================================================================
        ## 限定价格在 UpperLimit 和 LowerLimit 之间
        ## ---------------------------------------------------------------------
        if tempDirection == 'buy':
            tempPrice = self.priceBetweenUpperLower(
                tempBestPrice * (1-discount) + tempPriceTick * addTick, ticker)
        elif tempDirection == 'sell':
            tempPrice = self.priceBetweenUpperLower(
                tempBestPrice * (1+discount) - tempPriceTick * addTick, ticker)
        ## =====================================================================

        if volume:
            tempVolume = volume
        else:
            tempVolume = orderDict["volume"]

        if tempDirection == 'buy':
            id = self.buy(ticker, tempPrice, tempVolume)
        elif tempDirection == 'sell':
            id = self.sell(ticker, tempPrice, tempVolume)

        ## ----------------------------
        ## 如果是 list 要用 extend
        ## 如果只是单个 object 要用 append
        ## 这里假设股票交易只返回一个订单号
        ## ----------------------------
        orderIDList.append(id)
        tradingOrder[ticker+'-'+tempDirection]['vtOrderIDList'].append(id)

        self.timer[ticker]= datetime.now()


    ## =========================================================================
    ## william
    ## 从 MySQL 数据库获取交易订单
    ## =========================================================================
    def fetchTradingOrder(self, stage):
        """获取交易订单"""
        ## ---------------------------------------------------------------------
        tempOrder = vtFunction.dbMySQLQuery(
            self.asharesEngine.mainEngine.dataBase,
            """
            SELECT *
            FROM tradingOrder
            WHERE strategyID = '%s'
            AND TradingDay = '%s'
            AND stage = '%s'
            """ %(self.strategyID, vtFunction.tradingDate(), stage))
        if len(tempOrder) == 0:
            return {}
        ## ---------------------------------------------------------------------

        tradingOrderX = {}

        for i in xrange(len(tempOrder)):
            id = tempOrder.at[i,'instrumentID'].encode('ascii','ignore')
            tempKey = (id + '-' + tempOrder.at[i,'orderType']).encode('ascii','ignore')
            tradingOrderX[tempKey] = {
                'vtSymbol'      : id,
                'direction'     : tempOrder.at[i,'orderType'].encode('ascii','ignore'),
                'volume'        : tempOrder.at[i,'volume'],
                'tradingDay'    : tempOrder.at[i,'tradingDay'],
                'vtOrderIDList' : [],
                'subOrders'     : {},
                'lastTimer'     : datetime.now()
                }
        return tradingOrderX

    ############################################################################
    ## 更新 交易状态
    ## self.trading
    ## self.tradingBeginning
    ## self.tradingSplit
    ## self.tradingBetween
    ## self.tradingEnding
    ############################################################################
    def updateTradingStatus(self):
        t = datetime.now().time()
        ## =====================================================================
        ## 启动尾盘交易
        ## =====================================================================
        if time(9,29,55) <= t <= time(21, self.tradingCloseMinute1-1):
            self.tradingBeginning = True
            if t <= time(9, self.tradingOpenMinute2):
                self.tradingSplit = True
            else:
                self.tradingSplit = False
        else:
            self.tradingBeginning = False

        ## ---------------------------------------------------------------------
        if time(14, self.tradingCloseMinute1) <= t <= time(14, self.tradingCloseMinute2):
            self.tradingBetween = True
        else:
            self.tradingBetween = False

        ## ---------------------------------------------------------------------
        if time(14, self.tradingCloseMinute2, 45) <= t <= time(15, 01):
            self.tradingEnding = True
        else:
            self.tradingEnding = False
        ## ---------------------------------------------------------------------

########################################################################
class BarGenerator(object):
    """
    K线合成器，支持：
    1. 基于Tick合成1分钟K线
    2. 基于1分钟K线合成X分钟K线（X可以是2、3、5、10、15、30	）
    """

    #----------------------------------------------------------------------
    def __init__(self, onBar, xmin=0, onXminBar=None):
        """Constructor"""
        self.bar = None             # 1分钟K线对象
        self.onBar = onBar          # 1分钟K线回调函数
        
        self.xminBar = None         # X分钟K线对象
        self.xmin = xmin            # X的值
        self.onXminBar = onXminBar  # X分钟K线的回调函数
        
        self.lastTick = None        # 上一TICK缓存对象
        
    #----------------------------------------------------------------------
    def updateTick(self, tick):
        """TICK更新"""
        newMinute = False   # 默认不是新的一分钟
        
        # 尚未创建对象
        if not self.bar:
            self.bar = VtBarData()
            newMinute = True
        # 新的一分钟
        elif self.bar.datetime.minute != tick.datetime.minute:
            # 生成上一分钟K线的时间戳
            self.bar.datetime = self.bar.datetime.replace(second=0, microsecond=0)  # 将秒和微秒设为0
            self.bar.date = self.bar.datetime.strftime('%Y%m%d')
            self.bar.time = self.bar.datetime.strftime('%H:%M:%S.%f')
            
            # 推送已经结束的上一分钟K线
            self.onBar(self.bar)
            
            # 创建新的K线对象
            self.bar = VtBarData()
            newMinute = True
            
        # 初始化新一分钟的K线数据
        if newMinute:
            self.bar.vtSymbol = tick.vtSymbol
            self.bar.symbol = tick.symbol
            self.bar.exchange = tick.exchange

            self.bar.open = tick.lastPrice
            self.bar.high = tick.lastPrice
            self.bar.low = tick.lastPrice
        # 累加更新老一分钟的K线数据
        else:                                   
            self.bar.high = max(self.bar.high, tick.lastPrice)
            self.bar.low = min(self.bar.low, tick.lastPrice)

        # 通用更新部分
        self.bar.close = tick.lastPrice        
        self.bar.datetime = tick.datetime  
        self.bar.openInterest = tick.openInterest
   
        if self.lastTick:
            volumeChange = tick.volume - self.lastTick.volume   # 当前K线内的成交量
            self.bar.volume += max(volumeChange, 0)             # 避免夜盘开盘lastTick.volume为昨日收盘数据，导致成交量变化为负的情况
            
        # 缓存Tick
        self.lastTick = tick

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
            
            self.xminBar.datetime = bar.datetime    # 以第一根分钟K线的开始时间戳作为X分钟线的时间戳
        # 累加老K线
        else:
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
    

# ########################################################################
# class CtaSignal(object):
#     """
#     CTA策略信号，负责纯粹的信号生成（目标仓位），不参与具体交易管理
#     """

#     #----------------------------------------------------------------------
#     def __init__(self):
#         """Constructor"""
#         self.signalPos = 0      # 信号仓位
    
#     #----------------------------------------------------------------------
#     def onBar(self, bar):
#         """K线推送"""
#         pass
    
#     #----------------------------------------------------------------------
#     def onTick(self, tick):
#         """Tick推送"""
#         pass
        
#     #----------------------------------------------------------------------
#     def setSignalPos(self, pos):
#         """设置信号仓位"""
#         self.signalPos = pos
        
#     #----------------------------------------------------------------------
#     def getSignalPos(self):
#         """获取信号仓位"""
#         return self.signalPos
