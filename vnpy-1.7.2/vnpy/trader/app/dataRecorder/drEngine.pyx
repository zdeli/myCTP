# encoding: UTF-8

'''
该模块用于获取　CTP Tick Data　行情记录．
'''
from __future__ import division
import os,json,csv
import pandas as pd

from vnpy.event import Event
from vnpy.trader.vtEvent import *
from vnpy.trader import vtFunction
from vnpy.trader.vtObject import VtSubscribeReq
from vnpy.trader.vtGlobal import globalSetting

from .drBase import *
from .language import text

from datetime import datetime, time


########################################################################
cdef class DrEngine(object):
    """数据记录引擎"""

    cdef dict __dict__
    cdef public:
        list tickHeader
        list dataHeader
        int exitCounter
        int hour, minute, second

    #----------------------------------------------------------------------
    def __cinit__(self, mainEngine, eventEngine):
        global globalSetting
        """Constructor"""
        self.mainEngine = mainEngine
        self.eventEngine = eventEngine

        # 当前日期
        self.tradingDay = vtFunction.tradingDay()
        self.tradingDate = vtFunction.tradingDate()

        self.hour   = datetime.now().hour
        self.minute = datetime.now().minute
        self.second = datetime.now().second

        ## 目录
        self.PATH = os.path.abspath(os.path.dirname(__file__))

        ## ------------------
        # 载入设置，订阅行情
        self.loadSetting()
        ## ------------------

        self.tickHeader = ['timeStamp','date','time','symbol','exchange',
                          'lastPrice','preSettlementPrice','preClosePrice',
                          'openPrice','highestPrice','lowestPrice','closePrice',
                          'upperLimit','lowerLimit','settlementPrice','volume','turnover',
                          'preOpenInterest','openInterest','preDelta','currDelta',
                          'bidPrice1','bidPrice2','bidPrice3','bidPrice4','bidPrice5',
                          'askPrice1','askPrice2','askPrice3','askPrice4','askPrice5',
                          'bidVolume1','bidVolume2','bidVolume3','bidVolume4','bidVolume5',
                          'askVolume1','askVolume2','askVolume3','askVolume4','askVolume5',
                          'averagePrice']
        self.dataHeader = ['timeStamp','date','time',
                          'InstrumentID','ExchangeID',
                          'LastPrice','PreSettlementPrice','PreClosePrice',
                          'OpenPrice','HighestPrice','LowestPrice','ClosePrice',
                          'UpperLimitPrice','LowerLimitPrice','SettlementPrice','Volume','Turnover',
                          'PreOpenInterest','OpenInterest','PreDelta','CurrDelta',
                          'BidPrice1','BidPrice2','BidPrice3','BidPrice4','BidPrice5',
                          'AskPrice1','AskPrice2','AskPrice3','AskPrice4','AskPrice5',
                          'BidVolume1','BidVolume2','BidVolume3','BidVolume4','BidVolume5',
                          'AskVolume1','AskVolume2','AskVolume3','AskVolume4','AskVolume5',
                          'AveragePrice']
        self.tempFields = []
        ########################################################################
        self.DATA_PATH    = os.path.normpath(os.path.join(
                            globalSetting().vtSetting['DATA_PATH'],
                            globalSetting.accountID, 'TickData'))
        self.dataFile     = os.path.join(self.DATA_PATH,(str(self.tradingDay) + '.csv'))
        if not os.path.exists(self.dataFile):
            with open(self.dataFile, 'w') as f:
                wr = csv.writer(f)
                wr.writerow(self.tickHeader)
            f.close()
        ########################################################################

        ## =====================================================================
        self.DAY_START   = time(8, 00)       # 日盘启动和停止时间
        self.DAY_END     = time(15, 18)

        self.NIGHT_START = time(20, 00)      # 夜盘启动和停止时间
        self.NIGHT_END   = time(2, 32)
        self.exitCounter = 0
        ## =====================================================================

        # 注册事件监听
        self.registerEvent()

    #----------------------------------------------------------------------
    cpdef loadSetting(self):
        """加载配置"""
        ## =====================================================================
        # if self.mainEngine.subscribeAll:
        try:
            contractAll  = './temp/contractAll.csv'
            contractInfo = pd.read_csv(contractAll)
            self.contractDict = {}
            for i in xrange(len(contractInfo)):
                self.contractDict[contractInfo.loc[i]['symbol']] = contractInfo.loc[i].to_dict()
        except:
            self.mainEngine.writeLog(u'未找到需要订阅的合约信息: contractAll.csv',
                                     gatewayName = 'DATA_RECORDER')

        ## -----------------------------------------------------------------
        for k in self.contractDict.keys():
            contract = self.contractDict[k]
            req = VtSubscribeReq()
            req.symbol = contract['symbol']
            req.exchange = contract['exchange']

            if contract['symbol']:
                self.mainEngine.subscribe(req, contract['gatewayName'])
            ## -----------------------------------------------------------------
        ## =====================================================================

    #----------------------------------------------------------------------
    cpdef procecssTickEvent(self, event):
        """处理行情事件"""
        # data = [event.dict_['data'].__dict__[k] for k in self.tickHeader]
        # print data
        # with open(self.dataFile, 'a') as f:
        #     wr = csv.writer(f)
        #     wr.writerow([event.dict_['data'].__dict__[k] for k in self.tickHeader])
        
        # print event.dict_['InstrumentID']
        # print [event.dict_[k] for k in self.dataHeader]
        # print '\n'
        with open(self.dataFile, 'a') as f:
            wr = csv.writer(f)
            wr.writerow([event.dict_[k] for k in self.dataHeader])

        ## =====================================================================

    ############################################################################
    ## william
    ## 更新状态，需要订阅
    ############################################################################
    cpdef processTradingStatus(self, event):
        """控制交易开始与停止状态"""

        ## ------------------------
        self.hour   = datetime.now().hour
        self.minute = datetime.now().minute
        self.second = datetime.now().second
        ## ------------------------

        if (self.minute % 2 != 0 or self.second % 20 != 0):
            return

        ## ---------------------------------------------------------------------
        if ((self.hour == self.NIGHT_END.hour and self.minute >= self.NIGHT_END.minute) or
            (self.hour == self.DAY_END.hour and self.minute >= self.DAY_END.minute) or
            (self.hour in [self.NIGHT_START.hour, self.DAY_START.hour] and 50 <= self.minute < 55)):
            self.exitCounter += 1
            self.mainEngine.writeLog(u'即将退出系统，计数器：%s' %self.exitCounter,
                                     gatewayName = 'DATA_RECORDER')
            if self.exitCounter >= 3:
                os._exit(0)
        ## ---------------------------------------------------------------------

    #----------------------------------------------------------------------
    cdef registerEvent(self):
        """注册事件监听"""
        self.eventEngine.register(EVENT_TICK, self.procecssTickEvent)
        self.eventEngine.register(EVENT_TIMER, self.processTradingStatus)
