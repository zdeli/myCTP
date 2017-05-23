# encoding: UTF-8

'''
本文件中包含了CTA模块中用到的一些基础设置、类和常量等。
'''

from __future__ import division

# 把vn.trader根目录添加到python环境变量中
import sys
import os
sys.path.append('..')

################################################################################
## william
path = os.path.abspath(os.path.dirname(__file__))
sys.path.append(os.path.normpath(os.path.join(path, '..', 'main')))
################################################################################

# 常量定义
# CTA引擎中涉及到的交易方向类型
CTAORDER_BUY = u'买开'
CTAORDER_SELL = u'卖平'
CTAORDER_SHORT = u'卖开'
CTAORDER_COVER = u'买平'

# 本地停止单状态
STOPORDER_WAITING = u'等待中'
STOPORDER_CANCELLED = u'已撤销'
STOPORDER_TRIGGERED = u'已触发'

# 本地停止单前缀
STOPORDERPREFIX = 'CtaStopOrder.'

# 数据库名称
SETTING_DB_NAME = 'VnTrader_Setting_Db'
POSITION_DB_NAME = 'VnTrader_Position_Db'

TICK_DB_NAME = 'VnTrader_Tick_Db'
DAILY_DB_NAME = 'VnTrader_Daily_Db'
MINUTE_DB_NAME = 'VnTrader_1Min_Db'

# 引擎类型，用于区分当前策略的运行环境
ENGINETYPE_BACKTESTING = 'backtesting'  # 回测
ENGINETYPE_TRADING = 'trading'          # 实盘

# CTA引擎中涉及的数据类定义
from vtConstant import EMPTY_UNICODE, EMPTY_STRING, EMPTY_FLOAT, EMPTY_INT


################################################################################
class StopOrder(object):
    """本地停止单"""

    #---------------------------------------------------------------------------
    def __init__(self):
        """Constructor"""
        self.vtSymbol = EMPTY_STRING
        self.orderType = EMPTY_UNICODE
        self.direction = EMPTY_UNICODE
        self.offset = EMPTY_UNICODE
        self.price = EMPTY_FLOAT
        self.volume = EMPTY_INT
        
        self.strategy = None             # 下停止单的策略对象
        self.stopOrderID = EMPTY_STRING  # 停止单的本地编号 
        self.status = EMPTY_STRING       # 停止单状态


################################################################################
class CtaBarData(object):
    """K线数据"""

    #---------------------------------------------------------------------------
    def __init__(self):
        """Constructor"""
        self.vtSymbol = EMPTY_STRING        # vt系统代码
        self.symbol = EMPTY_STRING          # 代码
        self.exchange = EMPTY_STRING        # 交易所
    
        self.open = EMPTY_FLOAT             # OHLC
        self.high = EMPTY_FLOAT
        self.low = EMPTY_FLOAT
        self.close = EMPTY_FLOAT
        
        self.date = EMPTY_STRING            # bar开始的时间，日期
        self.time = EMPTY_STRING            # 时间
        self.datetime = None                # python的datetime时间对象
        
        self.volume = EMPTY_INT             # 成交量
        self.openInterest = EMPTY_INT       # 持仓量

################################################################################
## william
## 从 MySQL 导入的数据我, 我更改了里面的格式
## CtaMySQLBar
################################################################################
class CtaMySQLDailyData(object):
    """MySQL Data 导入的K线数据"""

    #----------------------------------------------------------------------
    def __init__(self):
        """Constructor"""
        self.TradingDay = EMPTY_STRING
        self.Sector = EMPTY_STRING
        self.InstrumentID = EMPTY_STRING

        self.OpenPrice = EMPTY_FLOAT
        self.HighPrice = EMPTY_FLOAT
        self.LowPrice = EMPTY_FLOAT
        self.ClosePrice = EMPTY_FLOAT

        self.Volume = EMPTY_INT 
        self.Turnover = EMPTY_FLOAT 
        
        self.OpenOpenInterest = EMPTY_INT 
        self.HighOpenInterst = EMPTY_INT 
        self.LowOpenInterest = EMPTY_INT 
        self.CloseOpenInterst = EMPTY_INT 
        
        self.UpperLimitPrice = EMPTY_FLOAT
        self.LowerLimitPrice = EMPTY_FLOAT
        self.SettlementPrice = EMPTY_FLOAT

################################################################################
## william
## 从 MySQL 导入的数据我, 我更改了里面的格式
## CtaMySQLBar
################################################################################
class CtaMySQLMinuteData(object):
    """MySQL Data 导入的K线数据"""

    #----------------------------------------------------------------------
    def __init__(self):
        """Constructor"""
        self.TradingDay      = EMPTY_STRING
        self.InstrumentID    = EMPTY_STRING
        self.Minute          = EMPTY_STRING
        self.NumericExchTime = EMPTY_FLOAT

        self.OpenPrice  = EMPTY_FLOAT
        self.HighPrice  = EMPTY_FLOAT
        self.LowPrice   = EMPTY_FLOAT
        self.ClosePrice = EMPTY_FLOAT

        self.Volume     = EMPTY_INT 
        self.Turnover   = EMPTY_FLOAT 
        
        # self.OpenOpenInterest = EMPTY_INT 
        # self.HighOpenInterst  = EMPTY_INT 
        # self.LowOpenInterest  = EMPTY_INT 
        # self.CloseOpenInterst = EMPTY_INT 
        
        self.UpperLimitPrice  = EMPTY_FLOAT
        self.LowerLimitPrice  = EMPTY_FLOAT
        # self.SettlementPrice  = EMPTY_FLOAT


################################################################################
class CtaTickData(object):
    """Tick数据"""
    ## 数据从 `gateway/ctpGateway/def onRtnDepthMarketData(self, data):` 来
    #---------------------------------------------------------------------------
    def __init__(self):
        """Constructor"""
        ## tick的时间
        self.timeStamp  = EMPTY_STRING              # 本地时间戳
        self.date       = EMPTY_STRING              # 日期
        self.time       = EMPTY_STRING              # 时间
        self.datetime   = None                      # python的datetime时间对象

        ## 代码
        self.symbol     = EMPTY_STRING              # 合约代码
        self.exchange   = EMPTY_STRING              # 交易所代码
        self.vtSymbol   = EMPTY_STRING              # vt系统代码

        ## 价格信息
        self.lastPrice          = EMPTY_FLOAT       # 最新成交价
        # self.preSettlementPrice = EMPTY_FLOAT 
        # self.preClosePrice      = EMPTY_FLOAT 
        self.openPrice          = EMPTY_FLOAT
        self.highestPrice       = EMPTY_FLOAT
        self.lowestPrice        = EMPTY_FLOAT
        self.closePrice         = EMPTY_FLOAT
        
        self.upperLimit = EMPTY_FLOAT               # 涨停价
        self.lowerLimit = EMPTY_FLOAT               # 跌停价

        ## 成交量, 成交额
        self.volume             = EMPTY_INT         # 最新成交量
        self.turnover           = EMPTY_INT         # 成交额

        # ## 持仓数据
        # self.preOpenInterest    = EMPTY_FLOAT 
        # self.openInterest       = EMPTY_INT         # 持仓量

        # ## 期权数据
        # self.preDelta           = EMPTY_FLOAT
        # self.currDelta          = EMPTY_FLOAT

        # 五档行情
        self.bidPrice1 = EMPTY_FLOAT
        self.bidPrice2 = EMPTY_FLOAT
        self.bidPrice3 = EMPTY_FLOAT
        self.bidPrice4 = EMPTY_FLOAT
        self.bidPrice5 = EMPTY_FLOAT
        
        self.askPrice1 = EMPTY_FLOAT
        self.askPrice2 = EMPTY_FLOAT
        self.askPrice3 = EMPTY_FLOAT
        self.askPrice4 = EMPTY_FLOAT
        self.askPrice5 = EMPTY_FLOAT        
        
        self.bidVolume1 = EMPTY_INT
        self.bidVolume2 = EMPTY_INT
        self.bidVolume3 = EMPTY_INT
        self.bidVolume4 = EMPTY_INT
        self.bidVolume5 = EMPTY_INT
        
        self.askVolume1 = EMPTY_INT
        self.askVolume2 = EMPTY_INT
        self.askVolume3 = EMPTY_INT
        self.askVolume4 = EMPTY_INT
        self.askVolume5 = EMPTY_INT    

        ########################################################################
        self.settlementPrice    = EMPTY_FLOAT
        self.averagePrice       = EMPTY_FLOAT   