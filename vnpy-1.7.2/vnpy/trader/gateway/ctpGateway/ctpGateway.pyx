# encoding: UTF-8

'''
vn.ctp的gateway接入

考虑到现阶段大部分CTP中的ExchangeID字段返回的都是空值
vtSymbol直接使用symbol
'''

import os,sys,io
import shelve,math
import json
import ujson
import pandas as pd
from copy import copy
from datetime import datetime, timedelta
from logging import *
from pprint import pprint

from vnpy.api.ctp import MdApi, TdApi, defineDict
from vnpy.trader import vtFunction
from vnpy.trader import hicloud
from vnpy.trader.vtConstant import *
from .language import text
from vnpy.trader.vtGlobal import globalSetting

# 以下为一些VT类型和CTP类型的映射字典
# 价格类型映射
cdef dict priceTypeMap = {}
priceTypeMap[PRICETYPE_LIMITPRICE] = defineDict["THOST_FTDC_OPT_LimitPrice"]
priceTypeMap[PRICETYPE_MARKETPRICE] = defineDict["THOST_FTDC_OPT_AnyPrice"]
cdef dict priceTypeMapReverse = {v: k for k, v in priceTypeMap.items()} 

# 方向类型映射
cdef dict directionMap = {}
directionMap[DIRECTION_LONG] = defineDict['THOST_FTDC_D_Buy']
directionMap[DIRECTION_SHORT] = defineDict['THOST_FTDC_D_Sell']
cdef dict directionMapReverse = {v: k for k, v in directionMap.items()}

# 开平类型映射
cdef dict offsetMap = {}
offsetMap[OFFSET_OPEN] = defineDict['THOST_FTDC_OF_Open']
offsetMap[OFFSET_CLOSE] = defineDict['THOST_FTDC_OF_Close']
offsetMap[OFFSET_CLOSETODAY] = defineDict['THOST_FTDC_OF_CloseToday']
offsetMap[OFFSET_CLOSEYESTERDAY] = defineDict['THOST_FTDC_OF_CloseYesterday']
cdef dict offsetMapReverse = {v:k for k,v in offsetMap.items()}

# 交易所类型映射
cdef dict exchangeMap = {}
exchangeMap[EXCHANGE_CFFEX] = 'CFFEX'
exchangeMap[EXCHANGE_SHFE] = 'SHFE'
exchangeMap[EXCHANGE_CZCE] = 'CZCE'
exchangeMap[EXCHANGE_DCE] = 'DCE'
exchangeMap[EXCHANGE_SSE] = 'SSE'
exchangeMap[EXCHANGE_SZSE] = 'SZSE'
exchangeMap[EXCHANGE_INE] = 'INE'
exchangeMap[EXCHANGE_UNKNOWN] = ''
cdef dict exchangeMapReverse = {v:k for k,v in exchangeMap.items()}

# 持仓类型映射
cdef dict posiDirectionMap = {}
posiDirectionMap[DIRECTION_NET] = defineDict["THOST_FTDC_PD_Net"]
posiDirectionMap[DIRECTION_LONG] = defineDict["THOST_FTDC_PD_Long"]
posiDirectionMap[DIRECTION_SHORT] = defineDict["THOST_FTDC_PD_Short"]
posiDirectionMapReverse = {v:k for k,v in posiDirectionMap.items()}

# 产品类型映射
cdef dict productClassMap = {}
productClassMap[PRODUCT_FUTURES] = defineDict["THOST_FTDC_PC_Futures"]
productClassMap[PRODUCT_OPTION] = defineDict["THOST_FTDC_PC_Options"]
productClassMap[PRODUCT_COMBINATION] = defineDict["THOST_FTDC_PC_Combination"]
cdef dict productClassMapReverse = {v:k for k,v in productClassMap.items()}
productClassMapReverse[defineDict["THOST_FTDC_PC_ETFOption"]] = PRODUCT_OPTION
productClassMapReverse[defineDict["THOST_FTDC_PC_Stock"]] = PRODUCT_EQUITY

# 委托状态映射
cdef dict statusMap = {}
statusMap[STATUS_ALLTRADED] = defineDict["THOST_FTDC_OST_AllTraded"]
statusMap[STATUS_PARTTRADED] = defineDict["THOST_FTDC_OST_PartTradedQueueing"]
statusMap[STATUS_NOTTRADED] = defineDict["THOST_FTDC_OST_NoTradeQueueing"]
statusMap[STATUS_CANCELLED] = defineDict["THOST_FTDC_OST_Canceled"]
cdef dict statusMapReverse = {v:k for k,v in statusMap.items()}

# 全局字典, key:symbol, value:exchange
cdef dict symbolExchangeDict = {}

from vnpy.event import *
from vnpy.trader.vtEvent import *
from vnpy.trader.vtObject import *


########################################################################
cdef class VtGateway(object):
    """交易接口"""

    cdef dict __dict__

    #----------------------------------------------------------------------
    def __cinit__(self, eventEngine, gatewayName):
        """Constructor"""
        self.eventEngine = eventEngine
        self.gatewayName = gatewayName
        
    #----------------------------------------------------------------------
    cpdef onTick(self, tick):
        """市场行情推送"""
        # 通用事件
        event1 = Event(type_=EVENT_TICK)
        event1.dict_['data'] = tick
        self.eventEngine.put(event1)
        
        # 特定合约代码的事件
        # 这个不能注释掉,否则在 UI 端无法显示行情数据
        event2 = Event(type_=EVENT_TICK+tick.vtSymbol)
        event2.dict_['data'] = tick
        self.eventEngine.put(event2)
    
    #----------------------------------------------------------------------
    cpdef onTrade(self, trade):
        """成交信息推送"""
        # 通用事件
        event1 = Event(type_=EVENT_TRADE)
        event1.dict_['data'] = trade
        self.eventEngine.put(event1)
        
        # 特定合约的成交事件
        # event2 = Event(type_=EVENT_TRADE+trade.vtSymbol)
        # event2.dict_['data'] = trade
        # self.eventEngine.put(event2)        
    
    #----------------------------------------------------------------------
    cpdef onOrder(self, order):
        """订单变化推送"""
        # 通用事件
        event1 = Event(type_=EVENT_ORDER)
        event1.dict_['data'] = order
        self.eventEngine.put(event1)
        
        # 特定订单编号的事件
        # event2 = Event(type_=EVENT_ORDER+order.vtOrderID)
        # event2.dict_['data'] = order
        # self.eventEngine.put(event2)
    
    #----------------------------------------------------------------------
    cpdef onPosition(self, position):
        """持仓信息推送"""
        # 通用事件
        event1 = Event(type_=EVENT_POSITION)
        event1.dict_['data'] = position
        self.eventEngine.put(event1)
        
        # 特定合约代码的事件
        # event2 = Event(type_=EVENT_POSITION+position.vtSymbol)
        # event2.dict_['data'] = position
        # self.eventEngine.put(event2)
    
    #----------------------------------------------------------------------
    cpdef onAccount(self, account):
        """账户信息推送"""
        # 通用事件
        event1 = Event(type_=EVENT_ACCOUNT)
        event1.dict_['data'] = account
        self.eventEngine.put(event1)
        
        # 特定合约代码的事件
        # event2 = Event(type_=EVENT_ACCOUNT+account.vtAccountID)
        # event2.dict_['data'] = account
        # self.eventEngine.put(event2)
    
    #----------------------------------------------------------------------
    cpdef onError(self, error):
        """错误信息推送"""
        # 通用事件
        event1 = Event(type_=EVENT_ERROR)
        event1.dict_['data'] = error
        self.eventEngine.put(event1)    
        
    #----------------------------------------------------------------------
    cpdef onLog(self, log):
        """日志推送"""
        # 通用事件
        event1 = Event(type_=EVENT_LOG)
        event1.dict_['data'] = log
        self.eventEngine.put(event1)
        
    #----------------------------------------------------------------------
    cpdef onContract(self, contract):
        """合约基础信息推送"""
        # 通用事件
        event1 = Event(type_=EVENT_CONTRACT)
        event1.dict_['data'] = contract
        self.eventEngine.put(event1)        


########################################################################
cdef class CtpGateway(VtGateway):
    """CTP接口"""

    cdef object VtGateway
    cdef public:
        dict lastTickDict, posInfoDict
        bint mdConnected, tdConnected, qryEnabled
        int qryCount, qryNextFunction, qryTrigger
        list qryFunctionList

    #----------------------------------------------------------------------
    def __cinit__(self, eventEngine, gatewayName='CTP'):
        """Constructor"""
        super(CtpGateway, self).__init__(eventEngine, gatewayName)
        
        ## 最后一个数据
        self.lastTickDict = {}
        ## 仓位信息
        self.posInfoDict = {}

        self.mdApi = CtpMdApi(self)     # 行情API
        self.tdApi = CtpTdApi(self)     # 交易API
        
        self.mdConnected = False        # 行情API连接状态，登录完成后为True
        self.tdConnected = False        # 交易API连接状态
        
        self.qryEnabled = False         # 循环查询
        
        self.CTPConnectFile = self.gatewayName + '_connect.json'
        path = os.path.normpath(
            os.path.join(
                os.path.dirname(__file__),
                '..', '..', '..', '..')
            )
        self.CTPConnectPath = os.path.join(path, 'trading', 'account', self.CTPConnectFile)

        
    #----------------------------------------------------------------------
    cpdef connect(self, str accountID):
        """连接"""
        try:
            f = file(self.CTPConnectPath)
        except IOError:
            log = VtLogData()
            log.gatewayName = self.gatewayName
            log.logContent = text.LOADING_ERROR
            self.onLog(log)
            return
        
        # 解析json文件
        info = json.load(f)
        setting = info[accountID]

        try:
            ## ------------------------------------
            for k in setting['status']:
                setting['status'][k] = True
            try:
                to_unicode = unicode
            except NameError:
                to_unicode = str
            # Write JSON file
            with io.open(self.CTPConnectPath, 'w', encoding='utf8') as outfile:
                info_json = json.dumps(info,
                                       indent       = 4, 
                                       sort_keys    = True,
                                       separators   = (',', ': '),
                                       ensure_ascii = False)
                outfile.write(to_unicode(info_json))
            ## ------------------------------------

            userID = str(setting['userID'])
            password = str(setting['password'])
            brokerID = str(setting['brokerID'])
            ## ------------------------------------
            # tdAddress = str(setting['tdAddress'])
            # mdAddress = str(setting['mdAddress'])
            ## ------------------------------------

            ## -------------------------------------
            ## -----------
            tdAddress = ''
            mdAddress = ''
            ## -----------
            for ip in setting['tdIP']:
                ## ----------------------------------
                if len(setting['tdIP']) == 1:
                    result = True
                else:
                    result = vtFunction.vetifyIP(ip)
                ## ----------------------------------
                if result is True:
                    tdAddress = "tcp://" + ip + ":" + setting['tdPort']
                    tdAddress = str(tdAddress)
                    break
                else:
                    continue

            for ip in setting['mdIP']:
                ## ----------------------------------
                if len(setting['tdIP']) == 1:
                    result = True
                else:
                    result = vtFunction.vetifyIP(ip)
                ## ----------------------------------
                if result is True:
                    mdAddress = "tcp://" + ip + ":" + setting['mdPort']
                    mdAddress = str(mdAddress)
                    break
                else:
                    continue
            # -------------------------------------

            # 如果json文件提供了验证码
            if 'authCode' in setting: 
                authCode = str(setting['authCode'])
                # userProductInfo = str(setting['userProductInfo'])
                userProductInfo = 'CTP'
                self.tdApi.requireAuthentication = True
            else:
                authCode = None
                # userProductInfo = None
                userProductInfo = 'CTP'
        except KeyError:
            log = VtLogData()
            log.gatewayName = self.gatewayName
            log.logContent = text.CONFIG_KEY_MISSING
            self.onLog(log)
            return            
        ########################################################################
        ## william
        ## 连接到
        ## 1. MdAPI
        ## 2. TdAPI
        ########################################################################
        # 创建行情和交易接口对象
        # 创建行情和交易接口对象
        if (tdAddress and mdAddress):
            self.mdApi.connect(userID, password, brokerID, mdAddress)
            self.tdApi.connect(userID, password, brokerID, tdAddress, authCode, userProductInfo)

        ## ---------------------------------------------------------------------
        # self.mdApi.connect(userID, password, brokerID, mdAddress)
        # self.tdApi.connect(userID, password, brokerID, tdAddress, authCode, userProductInfo)
        ## ---------------------------------------------------------------------
        
        # 初始化并启动查询
        self.initQuery()
    
    #----------------------------------------------------------------------
    cpdef subscribe(self, subscribeReq):
        """订阅行情"""
        self.mdApi.subscribe(subscribeReq)
        
    #----------------------------------------------------------------------
    cpdef sendOrder(self, orderReq):
        """发单"""
        return self.tdApi.sendOrder(orderReq)
        
    #----------------------------------------------------------------------
    cpdef cancelOrder(self, cancelOrderReq):
        """撤单"""
        self.tdApi.cancelOrder(cancelOrderReq)
        
    #----------------------------------------------------------------------
    cpdef qryAccount(self):
        """查询账户资金"""
        self.tdApi.qryAccount()
        
    #----------------------------------------------------------------------
    cpdef qryPosition(self):
        """查询持仓"""
        self.tdApi.qryPosition()
        
    #----------------------------------------------------------------------
    cpdef close(self):
        """关闭"""
        if self.mdConnected:
            self.mdApi.close()
        if self.tdConnected:
            self.tdApi.close()
        
    #----------------------------------------------------------------------
    cpdef initQuery(self):
        """初始化连续查询"""
        if self.qryEnabled:
            # 需要循环的查询函数列表
            self.qryFunctionList = [self.qryAccount, self.qryPosition]
            
            self.qryCount = 0           # 查询触发倒计时
            self.qryTrigger = 2         # 查询触发点
            self.qryNextFunction = 0    # 上次运行的查询函数索引
            
            self.startQuery()
    
    #----------------------------------------------------------------------
    cpdef query(self, event):
        """注册到事件处理引擎上的查询函数"""
        self.qryCount += 1
        
        if self.qryCount > self.qryTrigger:
            # 清空倒计时
            self.qryCount = 0
            
            # 执行查询函数
            function = self.qryFunctionList[self.qryNextFunction]
            function()
            
            # 计算下次查询函数的索引，如果超过了列表长度，则重新设为0
            self.qryNextFunction += 1
            if self.qryNextFunction == len(self.qryFunctionList):
                self.qryNextFunction = 0
    
    #----------------------------------------------------------------------
    cpdef startQuery(self):
        """启动连续查询"""
        self.eventEngine.register(EVENT_TIMER, self.query)
    
    #----------------------------------------------------------------------
    cpdef setQryEnabled(self, qryEnabled):
        """设置是否要启动循环查询"""
        self.qryEnabled = qryEnabled


########################################################################
class CtpMdApi(MdApi):
    """CTP行情API实现"""

    #----------------------------------------------------------------------
    def __init__(self, gateway):
        """Constructor"""
        super(CtpMdApi, self).__init__()
        
        self.gateway = gateway                  # gateway对象
        self.gatewayName = gateway.gatewayName  # gateway对象名称
        
        self.reqID = EMPTY_INT                  # 操作请求编号
        
        self.connectionStatus = False           # 连接状态
        self.loginStatus = False                # 登录状态
        
        self.subscribedSymbols = set()          # 已订阅合约代码        
        
        self.userID   = EMPTY_STRING            # 账号
        self.password = EMPTY_STRING            # 密码
        self.brokerID = EMPTY_STRING            # 经纪商代码
        self.address  = EMPTY_STRING            # 服务器地址

        self.lastTickFileds = [
            "vtSymbol", "lastPrice",
            "openPrice", "highestPrice", "lowestPrice",
            "bidPrice1", "askPrice1",
            "bidVolume1", "askVolume1",
            "upperLimit","lowerLimit",
            "exchange"]

        self.tradingDt = None               # 交易日datetime对象
        self.tradingDate = vtFunction.tradingDate()
        self.tradingDay = vtFunction.tradingDay()      # 交易日期
        self.lastTradingDate = vtFunction.lastTradingDate()
        self.lastTradingDay = vtFunction.lastTradingDay()
        self.tickTime = None                # 最新行情time对象

        # self.recorderFields = [
        #     "lastPrice",
        #     "openPrice","highestPrice","lowestPrice","closePrice",
        #     "upperLimit","lowerLimit",
        #     "preClosePrice","preOpenInterest","openInterest",
        #     "preDelta","currDelta",
        #     "bidPrice1","bidPrice2","bidPrice3","bidPrice4","bidPrice5",
        #     "askPrice1","askPrice2","askPrice3","askPrice4","askPrice5",
        #     "preSettlementPrice","settlementPrice","averagePrice"]

    #----------------------------------------------------------------------
    def onFrontConnected(self):
        """服务器连接"""
        self.connectionStatus = True
        self.writeLog(text.DATA_SERVER_CONNECTED)
        self.login()
    
    #----------------------------------------------------------------------  
    def onFrontDisconnected(self, n):
        """服务器断开"""
        self.connectionStatus = False
        self.loginStatus = False
        self.gateway.mdConnected = False
        self.writeLog(text.DATA_SERVER_DISCONNECTED)
        
    #---------------------------------------------------------------------- 
    def onHeartBeatWarning(self, n):
        """心跳报警"""
        # 因为API的心跳报警比较常被触发，且与API工作关系不大，因此选择忽略
        pass
    
    #----------------------------------------------------------------------   
    def onRspError(self, error, n, last):
        """错误回报"""
        self.writeError(error['ErrorID'], error['ErrorMsg'])
        
    #----------------------------------------------------------------------
    def onRspUserLogin(self, data, error, n, last):
        """登陆回报"""
        # 如果登录成功，推送日志信息
        if error['ErrorID'] == 0:
            self.loginStatus = True
            self.gateway.mdConnected = True
            
            self.writeLog(text.DATA_SERVER_LOGIN)

            # 重新订阅之前订阅的合约
            for subscribeReq in self.subscribedSymbols:
                self.subscribe(subscribeReq)
            
            # 登录时通过本地时间来获取当前的日期
            self.tradingDt = datetime.now()
            self.tradingDate = self.tradingDt.strftime('%Y%m%d')
                
        # 否则，推送错误信息
        else:
            self.writeError(error['ErrorID'], error['ErrorMsg'])
            

    #---------------------------------------------------------------------- 
    def onRspUserLogout(self, data, error, n, last):
        """登出回报"""
        # 如果登出成功，推送日志信息
        if error['ErrorID'] == 0:
            self.loginStatus = False
            self.gateway.mdConnected = False
            
            self.writeLog(text.DATA_SERVER_LOGOUT)
                
        # 否则，推送错误信息
        else:
            self.writeError(error['ErrorID'], error['ErrorMsg'])

    #----------------------------------------------------------------------  
    def onRspSubMarketData(self, data, error, n, last):
        """订阅合约回报"""
        # 通常不在乎订阅错误，选择忽略
        pass
        
    #----------------------------------------------------------------------  
    def onRspUnSubMarketData(self, data, error, n, last):
        """退订合约回报"""
        # 同上
        pass  
        
    #----------------------------------------------------------------------  
    def onRtnDepthMarketData(self, data):
        """行情推送"""
        ## ---------------------------------------------------------------------
        # 忽略无效的报价单
        if (data['LastPrice'] > 1.70e+100 or
            data['Volume'] <= 0):
            return
        # 过滤尚未获取合约交易所时的行情推送
        cdef char* symbol = data['InstrumentID']
        if symbol not in symbolExchangeDict:
            return
        ## ---------------------------------------------------------------------

        # 创建对象
        tick = VtTickData()
        tick.gatewayName = self.gatewayName
        tick.symbol = symbol
        tick.exchange = symbolExchangeDict[symbol]
        tick.vtSymbol = symbol      #'.'.join([tick.symbol, tick.exchange])
        
        # tick.timeStamp  = datetime.now().strftime('%Y%m%d %H:%M:%S.%f')
        # 上期所和郑商所可以直接使用，大商所需要转换
        ##################################### tick.date = data['ActionDay']
        tick.date = self.tradingDate
        # tick.time = '.'.join([data['UpdateTime'], str(data['UpdateMillisec']/100)])
        tick.time = '.'.join([data['UpdateTime'], str(data['UpdateMillisec'])])
        tick.datetime = datetime.strptime(' '.join([tick.date, tick.time]),
                                              '%Y%m%d %H:%M:%S.%f')  

        ## 价格信息
        tick.lastPrice          = round(data['LastPrice'],5)
        # tick.preSettlementPrice = data['PreSettlementPrice']
        tick.preClosePrice      = data['PreClosePrice']
        tick.openPrice          = round(data['OpenPrice'],5)
        tick.highestPrice       = data['HighestPrice']
        tick.lowestPrice        = data['LowestPrice']
        tick.closePrice         = data['ClosePrice']

        tick.upperLimit         = round(data['UpperLimitPrice'],5)
        tick.lowerLimit         = round(data['LowerLimitPrice'],5)

        ## 成交量, 成交额
        tick.volume   = data['Volume']
        tick.turnover = data['Turnover']

        ## 持仓数据
        # tick.preOpenInterest    = data['PreOpenInterest']
        tick.openInterest       = data['OpenInterest']

        # ## 期权数据
        # tick.preDelta           = data['PreDelta']
        # tick.currDelta          = data['CurrDelta']

        #! CTP只有一档行情
        tick.bidPrice1  = round(data['BidPrice1'],5)
        tick.bidVolume1 = data['BidVolume1']
        tick.askPrice1  = round(data['AskPrice1'],5)
        tick.askVolume1 = data['AskVolume1']

        ## ---------------------------------------------------------------------
        ## 不要删除，先注释掉
        ## ---------------------------------------------------------------------
        # tick.bidPrice2  = data['BidPrice2']
        # tick.bidVolume2 = data['BidVolume2']
        # tick.askPrice2  = data['AskPrice2']
        # tick.askVolume2 = data['AskVolume2']

        # tick.bidPrice3  = data['BidPrice3']
        # tick.bidVolume3 = data['BidVolume3']
        # tick.askPrice3  = data['AskPrice3']
        # tick.askVolume3 = data['AskVolume3']

        # tick.bidPrice4  = data['BidPrice4']
        # tick.bidVolume4 = data['BidVolume4']
        # tick.askPrice4  = data['AskPrice4']
        # tick.askVolume4 = data['AskVolume4']

        # tick.bidPrice5  = data['BidPrice5']
        # tick.bidVolume5 = data['BidVolume5']
        # tick.askPrice5  = data['AskPrice5']
        # tick.askVolume5 = data['AskVolume5']

        ########################################################################
        # tick.settlementPrice    = round(data['SettlementPrice'],5)
        # tick.averagePrice       = round(data['AveragePrice'],5)
        ########################################################################
        
        # # 大商所日期转换
        # if tick.exchange is EXCHANGE_DCE:
        #     newTime = datetime.strptime(tick.time, '%H:%M:%S.%f').time()    # 最新tick时间戳
            
        #     # 如果新tick的时间小于夜盘分隔，且上一个tick的时间大于夜盘分隔，则意味着越过了12点
        #     if (self.tickTime and 
        #         newTime < NIGHT_TRADING and
        #         self.tickTime > NIGHT_TRADING):
        #         self.tradingDt += timedelta(1)                          # 日期加1
        #         self.tradingDate = self.tradingDt.strftime('%Y%m%d')    # 生成新的日期字符串
                
        #     tick.date = self.tradingDate    # 使用本地维护的日期
        #     self.tickTime = newTime         # 更新上一个tick时间
        ## -------------------------------
        # cdef char* k
        ## -------------------------------
        # for k in self.recorderFields:
        #     if tick.__dict__[k] > 1.7e+100:
        #         tick.__dict__[k] = 0
        #     else:
        #         tick.__dict__[k] = round(tick.__dict__[k], 5)
        # ## -------------------------------
        ## ---------------------------------------------------------------------
        # print tick.__dict__
        self.gateway.onTick(tick)
        ## ---------------------------------------------------------------------
        ########################################################################
        ## william
        ## tick 数据返回到 /vn.trader/vtEngine.onTick()
        self.gateway.lastTickDict[symbol] = {k:tick.__dict__[k] for k in self.lastTickFileds}

    #---------------------------------------------------------------------- 
    def onRspSubForQuoteRsp(self, data, error, n, last):
        """订阅期权询价"""
        pass
        
    #----------------------------------------------------------------------
    def onRspUnSubForQuoteRsp(self, data, error, n, last):
        """退订期权询价"""
        pass 
        
    #---------------------------------------------------------------------- 
    def onRtnForQuoteRsp(self, data):
        """期权询价推送"""
        pass        
        
    #----------------------------------------------------------------------
    def connect(self, str userID, str password, str brokerID, str address):
        """初始化连接"""
        self.userID   = userID                # 账号
        self.password = password              # 密码
        self.brokerID = brokerID              # 经纪商代码
        self.address  = address               # 服务器地址
        
        # 如果尚未建立服务器连接，则进行连接
        if not self.connectionStatus:
            # 创建C++环境中的API对象，这里传入的参数是需要用来保存.con文件的文件夹路径
            path = vtFunction.getTempPath(self.gatewayName + '_')
            self.createFtdcMdApi(path)
            
            # 注册服务器地址
            self.registerFront(self.address)
            
            # 初始化连接，成功会调用onFrontConnected
            self.init()
            
        # 若已经连接但尚未登录，则进行登录
        else:
            if not self.loginStatus:
                self.login()
        
    #----------------------------------------------------------------------
    def subscribe(self, subscribeReq):
        """订阅合约"""
        # 这里的设计是，如果尚未登录就调用了订阅方法
        # 则先保存订阅请求，登录完成后会自动订阅
        if self.loginStatus:
            self.subscribeMarketData(str(subscribeReq.symbol))
        self.subscribedSymbols.add(subscribeReq)   
        
    #----------------------------------------------------------------------
    def login(self):
        """登录"""
        # 如果填入了用户名密码等，则登录
        cdef dict req = {}
        if self.userID and self.password and self.brokerID:
            req['UserID']   = self.userID
            req['Password'] = self.password
            req['BrokerID'] = self.brokerID
            self.reqID += 1
            self.reqUserLogin(req, self.reqID)    
    
    #----------------------------------------------------------------------
    def close(self):
        """关闭"""
        self.exit()
        
    #---------------------------------------------------------------------------
    def writeLog(self, content, logLevel = INFO):
        """发出日志"""
        log = VtLogData()
        log.gatewayName = self.gatewayName
        log.logContent  = content
        log.logLevel    = logLevel
        self.gateway.onLog(log)     

    #---------------------------------------------------------------------------
    def writeError(self, str errorID, errorMsg):
        """发出错误"""
        err = VtErrorData()
        err.gatewayName = self.gatewayName
        err.errorID     = errorID
        err.errorMsg    = errorMsg.decode('gbk')
        self.gateway.onError(err) 
        ## ---------------------------------------------------------------------
        content = u"[错误代码]:%s [提示信息] %s" %(err.errorID, err.errorMsg)
        if globalSetting.LOGIN:
            self.writeLog(content = content,
                          logLevel = ERROR)


########################################################################
class CtpTdApi(TdApi):
    """CTP交易API实现"""
    
    #----------------------------------------------------------------------
    def __init__(self, gateway):
        """API对象的初始化函数"""
        super(CtpTdApi, self).__init__()
        
        self.gateway     = gateway              # gateway对象
        self.gatewayName = gateway.gatewayName  # gateway对象名称
        self.dataBase    = globalSetting.accountID
        
        self.reqID = EMPTY_INT              # 操作请求编号
        self.orderRef = EMPTY_INT           # 订单编号
        
        self.connectionStatus = False       # 连接状态
        self.loginStatus = False            # 登录状态
        self.authStatus = False             # 验证状态
        self.loginFailed = False            # 登录失败（账号密码错误）
        
        self.userID = EMPTY_STRING          # 账号
        self.password = EMPTY_STRING        # 密码
        self.brokerID = EMPTY_STRING        # 经纪商代码
        self.address = EMPTY_STRING         # 服务器地址
        
        self.frontID = EMPTY_INT            # 前置机编号
        self.sessionID = EMPTY_INT          # 会话编号
        
        self.posDict = {}
        self.symbolExchangeDict = {}        # 保存合约代码和交易所的印射关系
        self.symbolSizeDict = {}            # 保存合约代码和合约大小的印射关系

        self.requireAuthentication = False
        
        self.contractDict  = {}
        self.orderDict     = {}
        self.tradeDict     = {}
        self.posInfoFields = ['vtSymbol', 'PosiDirection', 'position']
        self.dfAll         = pd.DataFrame()

        ## ---------------------------------------------------------------------
        # 当前日期 
        self.tradingDay = vtFunction.tradingDay()
        self.tradingDate = vtFunction.tradingDate()
        self.lastTradingDay = vtFunction.lastTradingDay()
        self.lastTradingDate = vtFunction.lastTradingDate()
        self.timer = {'account' : datetime.now(),
                      'position': datetime.now()}
        ## ---------------------------------------------------------------------

        ## -------------------------------
        ## 发送邮件预警
        self.sendMailTime = datetime.now()
        self.sendMailStatus = False
        self.sendMailContent = u''
        self.sendMailCounter = 0 
        ## -------------------------------

        ## 上一个交易日的净值
        self.preNav_account = vtFunction.dbMySQLQuery(
                        globalSetting.accountID,
                        """
                        select *
                        from accountInfo
                        where TradingDay < '%s'
                        order by -TradingDay limit 1
                        """ % self.tradingDay)
        self.preNav_nav = vtFunction.dbMySQLQuery(
                        globalSetting.accountID,
                        """
                        select *
                        from nav
                        where TradingDay < '%s'
                        order by -TradingDay limit 1
                        """ % self.tradingDay)

        if len(self.preNav_nav) == 0:
            if len(self.preNav_account) == 0:
                self.preNav = 1.0
            else:
                self.preNav = round(self.preNav_account.loc[0,'nav'], 5)
        else:
            self.preNav = round(self.preNav_nav.loc[0,'NAV'], 5)

        ## 截至到上一个交易日的总共基金份额
        self.totalShares = vtFunction.dbMySQLQuery(
                        globalSetting.accountID,
                        """
                        select *
                        from funding
                        where TradingDay < '%s'
                        """ % self.tradingDay)
        if len(self.totalShares) == 0:
            self.totalShares = 0
        else:
            self.totalShares  = int(self.totalShares.shares.sum())

        ## 从期货账户扣费的汇总统计
        self.feeInfo = vtFunction.dbMySQLQuery(
                        globalSetting.accountID,
                        """
                        select *
                        from fee
                        """)

        if len(self.feeInfo) == 0:
            self.feePre = 0
            self.feeToday = 0
        else:
            self.feePre = self.feeInfo.loc[self.feeInfo.TradingDay < self.tradingDate].Amount.sum()
            self.feeToday = self.feeInfo.loc[self.feeInfo.TradingDay == self.tradingDate].Amount.sum()

        self.feeAll = self.feePre + self.feeToday

        ## 如果有爬虫，则有 navInfo, 如 YunYang1
        self.navInfo = vtFunction.dbMySQLQuery(
                        globalSetting.accountID,
                        """
                        select *
                        from nav
                        where TradingDay = '%s'
                        """ % self.lastTradingDay)
        ## ---------------------------------------------------------------------

    #----------------------------------------------------------------------
    def onFrontConnected(self):
        """服务器连接"""
        self.connectionStatus = True
        self.writeLog(text.TRADING_SERVER_CONNECTED)
        
        if self.requireAuthentication:
            self.authenticate()
        else:
            self.login()
        
    #----------------------------------------------------------------------
    def onFrontDisconnected(self, n):
        """服务器断开"""
        self.connectionStatus = False
        self.loginStatus = False
        self.gateway.tdConnected = False
        self.writeLog(text.TRADING_SERVER_DISCONNECTED)
        
    #----------------------------------------------------------------------
    def onHeartBeatWarning(self, n):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspAuthenticate(self, data, error, n, last):
        """验证客户端回报"""
        if error['ErrorID'] == 0:
            self.authStatus = True
            self.writeLog(text.TRADING_SERVER_AUTHENTICATED)
            self.login()
        else:
            self.writeError(error['ErrorID'], error['ErrorMsg'])
        
    #----------------------------------------------------------------------
    def onRspUserLogin(self, data, error, n, last):
        """登陆回报"""
        # 如果登录成功，推送日志信息
        if error['ErrorID'] == 0:
            self.frontID = str(data['FrontID'])
            self.sessionID = str(data['SessionID'])
            self.loginStatus = True
            self.gateway.tdConnected = True
            
            self.writeLog(text.TRADING_SERVER_LOGIN)
            
            # 确认结算信息
            req = {}
            req['BrokerID'] = self.brokerID
            req['InvestorID'] = self.userID
            self.reqID += 1
            self.reqSettlementInfoConfirm(req, self.reqID)              
                
        # 否则，推送错误信息
        else:
            self.writeError(error['ErrorID'], error['ErrorMsg'])
            ## -----------------------------------------------------------------
            # 标识登录失败，防止用错误信息连续重复登录
            self.loginFailed =  True
        
    #----------------------------------------------------------------------
    def onRspUserLogout(self, data, error, n, last):
        """登出回报"""
        # 如果登出成功，推送日志信息
        if error['ErrorID'] == 0:
            self.loginStatus = False
            self.gateway.tdConnected = False
            self.writeLog(text.TRADING_SERVER_LOGOUT)
        # 否则，推送错误信息
        else:
            self.writeError(error['ErrorID'], error['ErrorMsg'])

    #----------------------------------------------------------------------
    def onRspUserPasswordUpdate(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspTradingAccountPasswordUpdate(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspOrderInsert(self, data, error, n, last):
        pass
        # """发单错误（柜台）"""
        # # 推送委托信息
        # ## =====================================================================
        # ## william
        # ## 拒单的返回信息
        # ## =====================================================================
        # order = VtOrderData()
        # order.gatewayName = self.gatewayName
        # order.symbol = data['InstrumentID']
        # order.exchange = exchangeMapReverse[data['ExchangeID']]
        # order.vtSymbol = order.symbol
        # order.orderID = data['OrderRef']
        # order.vtOrderID = '.'.join([self.gatewayName, order.orderID])        
        # order.direction = directionMapReverse.get(data['Direction'], DIRECTION_UNKNOWN)
        # order.offset = offsetMapReverse.get(data['CombOffsetFlag'], OFFSET_UNKNOWN)
        # order.status = STATUS_REJECTED
        # order.price = data['LimitPrice']
        # order.totalVolume = data['VolumeTotalOriginal']
        # # print order.__dict__
        # self.gateway.onOrder(order)

        # # 推送错误信息
        # # err = VtErrorData()
        # # err.gatewayName = self.gatewayName
        # # err.errorID = error['ErrorID']
        # # err.errorMsg = error['ErrorMsg'].decode('gbk')
        # # self.gateway.onError(err)
        # ## -----------------------------------------------------------------
        
        # ## =====================================================================
        # ## william
        # ## 打印拒单的信息信息
        # tempFields = ['orderID','vtSymbol','price','direction','offset',
        #               'tradedVolume','orderTime','status']
        # content = u"拒单的信息信息\n%s\n%s\n%s" %('-'*80,
        #     pd.DataFrame([[order.__dict__[k] for k in tempFields]], columns = tempFields),
        #     '-'*80)
        # self.writeLog(content, logLevel = ERROR)
        # self.writeError(error['ErrorID'], error['ErrorMsg'])


    #----------------------------------------------------------------------
    def onRspParkedOrderInsert(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspParkedOrderAction(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspOrderAction(self, data, error, n, last):
        """撤单错误（柜台）"""
        self.writeError(error['ErrorID'], error['ErrorMsg'])

    #----------------------------------------------------------------------
    def onRspQueryMaxOrderVolume(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspSettlementInfoConfirm(self, data, error, n, last):
        """确认结算信息回报"""
        self.writeLog(text.SETTLEMENT_INFO_CONFIRMED)
        
        # 查询合约代码
        self.reqID += 1
        self.reqQryInstrument({}, self.reqID)
        
    #----------------------------------------------------------------------
    def onRspRemoveParkedOrder(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspRemoveParkedOrderAction(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspExecOrderInsert(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspExecOrderAction(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspForQuoteInsert(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQuoteInsert(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQuoteAction(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspLockInsert(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspCombActionInsert(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryOrder(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryTrade(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryInvestorPosition(self, data, error, n, last):
        """持仓查询回报"""

        if not data['InstrumentID']:
            return
        
        # 获取持仓缓存对象
        posName = '.'.join([data['InstrumentID'], data['PosiDirection']])
        if posName in self.posDict:
            pos = self.posDict[posName]
        else:
            pos = VtPositionData()
            self.posDict[posName] = pos
            
            pos.gatewayName = self.gatewayName
            pos.symbol = data['InstrumentID']
            pos.vtSymbol = pos.symbol
            pos.direction = posiDirectionMapReverse.get(data['PosiDirection'], '')
            pos.vtPositionName = '.'.join([pos.vtSymbol, pos.direction]) 
            pos.commission = data['Commission']
        
        # 针对上期所持仓的今昨分条返回（有昨仓、无今仓），读取昨仓数据
        if data['YdPosition'] and not data['TodayPosition']:
            pos.ydPosition = data['Position']
            
        # 计算成本
        try:
            pos.size = self.symbolSizeDict[pos.symbol]
        except:
            if len(self.dfAll):
                pos.size = self.dfAll.loc[self.dfAll.symbol == data['InstrumentID'],'size'].values[0]
            else:
                pos.size = 1
            
        cost = pos.price * pos.position * pos.size
        
        # 汇总总仓
        pos.position += data['Position']
        pos.positionProfit += data['PositionProfit']
        
        # 计算持仓均价
        if pos.position and pos.size:    
            pos.price = (cost + data['PositionCost']) / (pos.position * pos.size)
        
        # 读取冻结
        if pos.direction is DIRECTION_LONG: 
            pos.frozen += data['LongFrozen']
        else:
            pos.frozen += data['ShortFrozen']
        ## =====================================================================
        try:
            tempPrice = self.gateway.lastTickDict[pos.vtSymbol]['lastPrice']
        except:
            tempPrice = pos.price
        self.gateway.posInfoDict[pos.vtSymbol] = {'vtSymbol':pos.vtSymbol,
                                                  'position':pos.position,
                                                  'price':tempPrice,
                                                  'size':pos.size}
        ## =====================================================================
        pos.value = format(tempPrice * pos.size * pos.position, ',')
        # 查询回报结束
        if last:
            # 遍历推送
            for pos in self.posDict.values():
                self.gateway.onPosition(pos)
            # 清空缓存
            self.posDict.clear()
        
    #----------------------------------------------------------------------
    def onRspQryTradingAccount(self, data, error, n, last):
        """资金账户查询回报"""
        ## ---------------------------------------------------------------------
        ## 不要那么频繁的更新数据
        if (datetime.now() - self.timer['account']).seconds <= 15:
            return
        self.timer['account'] = datetime.now()
        ## ---------------------------------------------------------------------

        cdef int depositShares, withdrawShares

        """
        onRspQryTradingAccount 获得的　data 可以参考:
        vnpy/api/ctp/py3/pyscript/ctp_struct.py
        #资金账户
        CThostFtdcTradingAccountField = {}
        """
        account = VtAccountData()
        account.gatewayName = self.gatewayName

        # 账户代码
        
        # account.TradingDay = self.tradingDay
        # account.updateTime  = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        account.accountID = '.'.join([self.gatewayName, data['AccountID']])
        account.accountName = globalSetting.accountName
        # account.vtAccountID = '.'.join([self.gatewayName, account.accountID])

        account.preBalance = round(data['PreBalance'],2)
        account.balance = round(data['PreBalance'] - data['PreCredit'] - data['PreMortgage'] +
                           data['Mortgage'] - data['Withdraw'] + data['Deposit'] +
                           data['CloseProfit'] + data['PositionProfit'] + data['CashIn'] -
                           data['Commission'],2)
        account.available = round(data['Available'],2)

        account.value = sum(
                           [self.gateway.posInfoDict[k]['position'] * self.gateway.posInfoDict[k]['price'] * self.gateway.posInfoDict[k]['size'] for k in self.gateway.posInfoDict.keys()]
                            )

        if self.gateway.initialCapital:
            account.leverage   = round(account.value / self.gateway.initialCapital,2)

        account.commission     = round(data['Commission'],2)
        account.margin         = round(data['CurrMargin'],2)
        account.closeProfit    = round(data['CloseProfit'],2)
        account.positionProfit = round(data['PositionProfit'],2)
        account.profit         = account.closeProfit + account.positionProfit
        account.deposit        = round(data['Deposit'],2) + globalSetting.accountDepositEquityToday
        account.withdraw       = round(data['Withdraw'],2)
        account.netIncome      = account.deposit - account.withdraw

        ## ----------------------------------------------
        # if (globalSetting.accountID in ['YongAnLYB', 'ShenWanYYX'] and 
        #     not ( (datetime.now().hour == 14 and datetime.now().minute > 50) or 
        #           (datetime.now().hour == 15 and datetime.now().minute <= 15) ) ):
        #     account.closeProfit = 0
        ## ----------------------------------------------

        ## ----------------------
        ## 从出入金的角度看，
        ## 会比申购／赎回往后延迟一天
        ## 1.出金: --> preNav
        ## 2.入金: --> nav
        ## ----------------------

        ## ---------------------------------------------------------------------
        withdrawShares = -int(account.withdraw / self.preNav)
        if withdrawShares != 0:
            dfData = [self.tradingDay, account.withdraw, self.preNav, withdrawShares, u'基金申购']
            df = pd.DataFrame(
                [dfData], 
                columns = ['TradingDay','capital','price','shares','investor'])
            vtFunction.dbMySQLSend(
                dbName = globalSetting.accountID, 
                query  = """delete from funding
                            where TradingDay = '%s'""" % self.tradingDay)
            vtFunction.saveMySQL(
                df = df, 
                db = globalSetting.accountID, 
                tbl = 'funding',
                over = 'append', 
                sourceID = 'ctpGateway.onRspQryTradingAccount()')
        ## 当日应该扣除的所有份额数量
        account.shares = self.totalShares + withdrawShares
        ## ---------------------------------------------------------------------

        ## 当日从期货账户扣费情况
        ## 需要手动核对
        account.fee = self.feeToday

        if len(self.navInfo) == 0:
            account.banking = 0
            account.flowCapital = self.gateway.flowCapital
        else:
            account.banking = self.navInfo.Bank.values[0]
            account.flowCapital = self.navInfo.Currency.values[0]

        ## 当日总资产
        account.asset = account.balance + account.flowCapital
        ## ---------------------------------------------------------------------
        if account.asset:
            ## --------------
            ## 占用的保证金比例
            ## --------------
            account.marginPct = round(account.margin / account.asset,4) * 100
            ## -----------------------------------------------------------------
            if account.marginPct > 70:
                msg = u"""账户 [%s] 
                       保证金占比%s%%，超过限制70%%
                       """ %(globalSetting.accountName, account.marginPct)
                if not self.sendMailStatus:
                    self.sendMailStatus = True
                    self.sendMailTime = datetime.now()
                    self.writeLog(msg)
                    hicloud.sendMail(globalSetting.accountName, msg, 'WARN')
                elif ((datetime.now() - self.sendMailTime).seconds > 300 and 
                      (self.sendMailCounter < 5)):
                    self.sendMailTime = datetime.now()
                    self.sendMailCounter += 1
                    self.writeLog(msg)
                    hicloud.sendMail(globalSetting.accountName, msg, 'WARN')
            ## -----------------------------------------------------------------
            ## 当日净值
            account.nav = round((account.asset + self.feeAll + 
                                 account.banking + account.withdraw) / account.shares,4)

            ## 当日申购的基金
            ## ---------------------------------------------------------------------
            depositShares = int(account.deposit / account.nav)
            if depositShares != 0:
                dfData = [self.tradingDay, account.deposit, self.preNav, depositShares, u'基金赎回']
                df = pd.DataFrame(
                    [dfData], 
                    columns = ['TradingDay','capital','price','shares','investor'])
                vtFunction.dbMySQLSend(dbName = globalSetting.accountID, 
                                       query = """delete from funding
                                                  where TradingDay = '%s'""" % self.tradingDay)
                vtFunction.saveMySQL(
                    df = df,
                    db = globalSetting.accountID,
                    tbl = 'funding',
                    over = 'append',
                    sourceID = 'ctpGateway')
            ## 当日应该计入的所有份额数量
            account.shares = self.totalShares + depositShares
            ## ---------------------------------------------------------------------

            account.shares = account.shares + withdrawShares
            ## 当日收益波动
            account.chgpct = round(account.nav / self.preNav - 1, 4) * 100
            ## 合约价值转化
            account.value = format(account.value, ',')
        ## ---------------------------------------------------------------------
        # 推送
        self.gateway.onAccount(account)
        
    #----------------------------------------------------------------------
    def onRspQryInvestor(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryTradingCode(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryInstrumentMarginRate(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryInstrumentCommissionRate(self, data, error, n, last):
        """"""
        pass

    #----------------------------------------------------------------------
    def onRspQryExchange(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryProduct(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryInstrument(self, data, error, n, last):
        """合约查询回报"""
        contract = VtContractData()
        contract.gatewayName = self.gatewayName

        contract.symbol = data['InstrumentID']
        contract.exchange = exchangeMapReverse[data['ExchangeID']]
        contract.vtSymbol = contract.symbol #'.'.join([contract.symbol, contract.exchange])
        contract.name = data['InstrumentName'].decode('GBK')

        # 合约数值
        contract.size = data['VolumeMultiple']
        contract.priceTick = data['PriceTick']
        contract.strikePrice = data['StrikePrice']
        contract.underlyingSymbol = data['UnderlyingInstrID']
        contract.productClass = productClassMapReverse.get(data['ProductClass'], PRODUCT_UNKNOWN)
        contract.expiryDate = data['ExpireDate']
        
        # 期权类型
        if contract.productClass is PRODUCT_OPTION:
            if data['OptionsType'] == '1':
                contract.optionType = OPTION_CALL
            elif data['OptionsType'] == '2':
                contract.optionType = OPTION_PUT

        contract.volumeMultiple = data['VolumeMultiple']

        if data['LongMarginRatio'] < 1e+99 and data['ShortMarginRatio'] < 1e+99:
            contract.longMarginRatio  = round(data['LongMarginRatio'],5)
            contract.shortMarginRatio = round(data['ShortMarginRatio'],5)
        # 缓存代码和交易所的印射关系
        self.symbolExchangeDict[contract.symbol] = contract.exchange
        self.symbolSizeDict[contract.symbol] = contract.size

        # 推送
        self.gateway.onContract(contract)
        ## =====================================================================
        ## william
        ## ---------------------------------------------------------------------
        self.contractDict[contract.symbol]   = contract
        self.contractDict[contract.vtSymbol] = contract
        ## =====================================================================

        # 缓存合约代码和交易所映射
        symbolExchangeDict[contract.symbol] = contract.exchange

        if last:
            dfHeader = ['symbol','vtSymbol','name','productClass','gatewayName','exchange',
                        'priceTick','size','shortMarginRatio','longMarginRatio',
                        'optionType','underlyingSymbol','strikePrice']
            dfData   = []
            for k in self.contractDict.keys():
                temp = self.contractDict[k].__dict__
                dfData.append([temp[kk] for kk in dfHeader])
            df = pd.DataFrame(dfData, columns = dfHeader)

            reload(sys) # reload 才能调用 setdefaultencoding 方法
            sys.setdefaultencoding('utf-8')

            df.to_csv('./temp/contract.csv', index = False)
            if not os.path.exists('./temp/contractAll.csv'):
                df.to_csv('./temp/contractAll.csv', index = False)

            ## =================================================================
            try:
                self.dfAll = pd.read_csv('./temp/contractAll.csv')
                for i in range(df.shape[0]):
                    if df.at[i,'symbol'] not in self.dfAll.symbol.values:
                        self.dfAll = self.dfAll.append(df.loc[i], ignore_index = True)
                self.dfAll.to_csv('./temp/contractAll.csv', index = False)
            except:
                None
            ## =================================================================
            try:
                self.contractFileName = './temp/ContractData.vt'
                f = shelve.open(self.contractFileName)
                f['data'] = self.contractDict
                f.close()
            except:
                None
            ## =================================================================
            self.writeLog(text.CONTRACT_DATA_RECEIVED)
            ## 交易合约信息获取是否成功
            globalSetting.LOGIN = True
            self.writeLog(u'账户登录成功')
        
    #----------------------------------------------------------------------
    def onRspQryDepthMarketData(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQrySettlementInfo(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryTransferBank(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryInvestorPositionDetail(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryNotice(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQrySettlementInfoConfirm(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryInvestorPositionCombineDetail(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryCFMMCTradingAccountKey(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryEWarrantOffset(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryInvestorProductGroupMargin(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryExchangeMarginRate(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryExchangeMarginRateAdjust(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryExchangeRate(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQrySecAgentACIDMap(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryProductExchRate(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryProductGroup(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryOptionInstrTradeCost(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryOptionInstrCommRate(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryExecOrder(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryForQuote(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryQuote(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryLock(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryLockPosition(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryInvestorLevel(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryExecFreeze(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryCombInstrumentGuard(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryCombAction(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryTransferSerial(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryAccountregister(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspError(self, error, n, last):
        """错误回报"""
        self.writeError(error['ErrorID'], error['ErrorMsg'])

    #----------------------------------------------------------------------
    def onRtnOrder(self, data):
        """报单回报"""
        ## -----------------------------------------------
        # 更新最大报单编号
        # newref = data['OrderRef']
        # self.orderRef = max(self.orderRef, int(newref))
        ## -----------------------------------------------

        self.orderRef = max(self.orderRef, int(data['OrderRef']))

        # 创建报单数据对象
        order = VtOrderData()
        order.gatewayName = self.gatewayName
        
        # 保存代码和报单号
        order.symbol = data['InstrumentID']
        order.exchange = exchangeMapReverse[data['ExchangeID']]
        order.vtSymbol = order.symbol #'.'.join([order.symbol, order.exchange])
        
        order.orderID = data['OrderRef']
        # CTP的报单号一致性维护需要基于frontID, sessionID, orderID三个字段
        # 但在本接口设计中，已经考虑了CTP的OrderRef的自增性，避免重复
        # 唯一可能出现OrderRef重复的情况是多处登录并在非常接近的时间内（几乎同时发单）
        # 考虑到VtTrader的应用场景，认为以上情况不会构成问题
        order.vtOrderID = '.'.join([self.gatewayName, order.orderID])        
        
        order.direction = directionMapReverse.get(data['Direction'], DIRECTION_UNKNOWN)
        order.offset = offsetMapReverse.get(data['CombOffsetFlag'], OFFSET_UNKNOWN)
        order.status = statusMapReverse.get(data['OrderStatus'], STATUS_UNKNOWN)            
            
        # 价格、报单量等数值
        order.price = data['LimitPrice']
        order.totalVolume = data['VolumeTotalOriginal']
        order.tradedVolume = data['VolumeTraded']
        order.orderTime = data['InsertTime']
        order.cancelTime = data['CancelTime']
        order.frontID = data['FrontID']
        order.sessionID = data['SessionID']
        
        # 推送
        self.gateway.onOrder(order)
        
    #----------------------------------------------------------------------
    def onRtnTrade(self, data):
        """成交回报"""
        # 创建报单数据对象
        trade = VtTradeData()
        trade.gatewayName = self.gatewayName
        
        # 保存代码和报单号
        trade.symbol = data['InstrumentID']
        trade.exchange = exchangeMapReverse[data['ExchangeID']]
        trade.vtSymbol = trade.symbol #'.'.join([trade.symbol, trade.exchange])
        
        trade.tradeID = data['TradeID']
        trade.vtTradeID = '.'.join([self.gatewayName, trade.tradeID])
        
        trade.orderID = data['OrderRef']
        trade.vtOrderID = '.'.join([self.gatewayName, trade.orderID])
        
        # 方向
        trade.direction = directionMapReverse.get(data['Direction'], '')
        # 开平
        trade.offset = offsetMapReverse.get(data['OffsetFlag'], '')
            
        # 价格、报单量等数值
        trade.price = data['Price']
        trade.volume = data['Volume']
        trade.tradeTime = data['TradeTime']
        
        # 推送
        self.gateway.onTrade(trade)


    #----------------------------------------------------------------------
    def onErrRtnOrderInsert(self, data, error):
        """发单错误回报（交易所）"""
        ## =====================================================================
        ## william
        ## 拒单的返回信息
        ## =====================================================================
        if not globalSetting.LOGIN:
            return
        # 推送委托信息
        order = VtOrderData()
        order.gatewayName = self.gatewayName
        order.symbol = data['InstrumentID']
        order.exchange = exchangeMapReverse[data['ExchangeID']]
        order.vtSymbol = order.symbol
        order.orderID = data['OrderRef']
        order.vtOrderID = '.'.join([self.gatewayName, order.orderID])        
        order.direction = directionMapReverse.get(data['Direction'], DIRECTION_UNKNOWN)
        order.offset = offsetMapReverse.get(data['CombOffsetFlag'], OFFSET_UNKNOWN)
        order.status = STATUS_REJECTED
        order.price = data['LimitPrice']
        order.totalVolume = data['VolumeTotalOriginal']
        self.gateway.onOrder(order)
        
        ## =====================================================================
        ## william
        ## 打印拒单的信息信息
        tempFields = ['orderID','vtSymbol','price','direction','offset',
                      'tradedVolume','orderTime','status']
        content = u"拒单的详细信息\n%s\n%s\n%s\n" %('-'*80,
            pd.DataFrame([[order.__dict__[k] for k in tempFields]], columns = tempFields).to_string(index=False),
            '-'*80)
        self.writeLog(content, logLevel = ERROR)
        self.writeError(error['ErrorID'], error['ErrorMsg'])

    #----------------------------------------------------------------------
    def onErrRtnOrderAction(self, data, error):
        """撤单错误回报（交易所）"""
        self.writeError(error['ErrorID'], error['ErrorMsg'])

    #----------------------------------------------------------------------
    def onRtnInstrumentStatus(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnTradingNotice(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnErrorConditionalOrder(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnExecOrder(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnExecOrderInsert(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnExecOrderAction(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnForQuoteInsert(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnQuote(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnQuoteInsert(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnQuoteAction(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnForQuoteRsp(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnCFMMCTradingAccountToken(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnLock(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnLockInsert(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnCombAction(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnCombActionInsert(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryContractBank(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryParkedOrder(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryParkedOrderAction(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryTradingNotice(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryBrokerTradingParams(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQryBrokerTradingAlgos(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQueryCFMMCTradingAccountToken(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnFromBankToFutureByBank(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnFromFutureToBankByBank(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnRepealFromBankToFutureByBank(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnRepealFromFutureToBankByBank(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnFromBankToFutureByFuture(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnFromFutureToBankByFuture(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnRepealFromBankToFutureByFutureManual(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnRepealFromFutureToBankByFutureManual(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnQueryBankBalanceByFuture(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnBankToFutureByFuture(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnFutureToBankByFuture(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnRepealBankToFutureByFutureManual(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnRepealFutureToBankByFutureManual(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onErrRtnQueryBankBalanceByFuture(self, data, error):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnRepealFromBankToFutureByFuture(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnRepealFromFutureToBankByFuture(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspFromBankToFutureByFuture(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspFromFutureToBankByFuture(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRspQueryBankAccountMoneyByFuture(self, data, error, n, last):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnOpenAccountByBank(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnCancelAccountByBank(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def onRtnChangeAccountByBank(self, data):
        """"""
        pass
        
    #----------------------------------------------------------------------
    def connect(self, userID, password, brokerID, address, authCode, userProductInfo):
        """初始化连接"""
        self.userID = userID                # 账号
        self.password = password            # 密码
        self.brokerID = brokerID            # 经纪商代码
        self.address = address              # 服务器地址
        self.authCode = authCode            #验证码
        self.userProductInfo = userProductInfo  #产品信息
        
        # 如果尚未建立服务器连接，则进行连接
        if not self.connectionStatus:
            # 创建C++环境中的API对象，这里传入的参数是需要用来保存.con文件的文件夹路径
            path = vtFunction.getTempPath(self.gatewayName + '_')
            self.createFtdcTraderApi(path)
            
            # 设置数据同步模式为推送从今日开始所有数据
            self.subscribePrivateTopic(0)
            self.subscribePublicTopic(0)            
            
            # 注册服务器地址
            self.registerFront(self.address)
            # 初始化连接，成功会调用onFrontConnected
            self.init()
            
        # 若已经连接但尚未登录，则进行登录
        else:
            if self.requireAuthentication and not self.authStatus:
                self.authenticate()
            elif not self.loginStatus:
                self.login()
    
    #----------------------------------------------------------------------
    def login(self):
        """连接服务器"""
        # 如果之前有过登录失败，则不再进行尝试
        if self.loginFailed:
            return
        cdef dict req = {}
        # 如果填入了用户名密码等，则登录
        if self.userID and self.password and self.brokerID:
            req['UserID'] = self.userID
            req['Password'] = self.password
            req['BrokerID'] = self.brokerID
            self.reqID += 1
            self.reqUserLogin(req, self.reqID)   
            
    #----------------------------------------------------------------------
    def authenticate(self):
        """申请验证"""
        cdef dict req = {}
        if self.userID and self.brokerID and self.authCode and self.userProductInfo:
            req['UserID'] = self.userID
            req['BrokerID'] = self.brokerID
            req['AuthCode'] = self.authCode
            req['UserProductInfo'] = self.userProductInfo
            self.reqID += 1
            self.reqAuthenticate(req, self.reqID)

    #----------------------------------------------------------------------
    def qryAccount(self):
        """查询账户"""
        self.reqID += 1
        self.reqQryTradingAccount({}, self.reqID)
        
    #----------------------------------------------------------------------
    def qryPosition(self):
        """查询持仓"""
        self.reqID += 1
        cdef dict req = {}
        req['BrokerID'] = self.brokerID
        req['InvestorID'] = self.userID
        self.reqQryInvestorPosition(req, self.reqID)
        
    #----------------------------------------------------------------------
    def sendOrder(self, orderReq):
        """发单"""
        self.reqID += 1
        self.orderRef += 1
        
        cdef dict req = {}
        
        req['InstrumentID'] = orderReq.symbol
        req['LimitPrice'] = orderReq.price
        req['VolumeTotalOriginal'] = orderReq.volume
        
        # 下面如果由于传入的类型本接口不支持，则会返回空字符串
        req['OrderPriceType'] = priceTypeMap.get(orderReq.priceType, '')
        req['Direction'] = directionMap.get(orderReq.direction, '')
        req['CombOffsetFlag'] = offsetMap.get(orderReq.offset, '')
            
        req['OrderRef'] = str(self.orderRef)
        req['InvestorID'] = self.userID
        req['UserID'] = self.userID
        req['BrokerID'] = self.brokerID
        
        req['CombHedgeFlag'] = defineDict['THOST_FTDC_HF_Speculation']       # 投机单
        req['ContingentCondition'] = defineDict['THOST_FTDC_CC_Immediately'] # 立即发单
        req['ForceCloseReason'] = defineDict['THOST_FTDC_FCC_NotForceClose'] # 非强平
        req['IsAutoSuspend'] = 0                                             # 非自动挂起
        req['TimeCondition'] = defineDict['THOST_FTDC_TC_GFD']               # 今日有效
        req['VolumeCondition'] = defineDict['THOST_FTDC_VC_AV']              # 任意成交量
        req['MinVolume'] = 1                                                 # 最小成交量为1
        
        ## ---------------------------------------------------------------------
        # 判断FAK和FOK
        if orderReq.priceType == PRICETYPE_FAK:
            req['OrderPriceType'] = defineDict["THOST_FTDC_OPT_LimitPrice"]
            req['TimeCondition'] = defineDict['THOST_FTDC_TC_IOC']
            req['VolumeCondition'] = defineDict['THOST_FTDC_VC_AV']
        if orderReq.priceType == PRICETYPE_FOK:
            req['OrderPriceType'] = defineDict["THOST_FTDC_OPT_LimitPrice"]
            req['TimeCondition'] = defineDict['THOST_FTDC_TC_IOC']
            req['VolumeCondition'] = defineDict['THOST_FTDC_VC_CV']   
        ## ---------------------------------------------------------------------

        ## ---------------------------------------------------------------------
        self.reqOrderInsert(req, self.reqID)
        ## ---------------------------------------------------------------------

        ## =====================================================================
        ## william
        ## orderReq
        orderReq.orderTime   = datetime.now().strftime('%H:%M:%S')
        orderReq.orderID     = self.orderRef
        orderReq.vtOrderID   = self.gatewayName + '.' + str(self.orderRef)
        orderReq.tradeStatus = u'未成交'      
        ## ---------------------------------------------------------------------
        cdef list tempFields = ['vtOrderID','vtSymbol','price','direction','offset',
                      'volume','orderTime','tradeStatus']
        ## ---------------------------------------------------------------------
        content = u'下单的详细信息\n%s\n%s\n%s' %('-'*80,
            pd.DataFrame([orderReq.__dict__.values()], columns = orderReq.__dict__.keys())[tempFields].to_string(index=False),
            '-'*80)
        self.writeLog(content)
        ## --------------------------------------------------------------------- 
        # 返回订单号（字符串），便于某些算法进行动态管理
        cdef str vtOrderID = '.'.join([self.gatewayName, str(self.orderRef)])
        return vtOrderID
        ## =====================================================================

    
    #----------------------------------------------------------------------
    def cancelOrder(self, cancelOrderReq):
        """撤单"""
        self.reqID += 1

        cdef dict req = {}
        
        req['InstrumentID'] = cancelOrderReq.symbol
        req['ExchangeID']   = cancelOrderReq.exchange
        req['OrderRef']     = cancelOrderReq.orderID
        req['FrontID']      = cancelOrderReq.frontID
        req['SessionID']    = cancelOrderReq.sessionID
        req['ActionFlag']   = defineDict['THOST_FTDC_AF_Delete']
        req['BrokerID']     = self.brokerID
        req['InvestorID']   = self.userID

        self.reqOrderAction(req, self.reqID)
        # ## ---------------------------------------------------------------------
        # ## william
        # ## 打印撤单的详细信息
        ## ---------------------------------------------------------------------
        content = u'撤单的详细信息\n%s%s\n%s\n' %(
            '-'*80+'\n',
            pd.DataFrame([req.values()], columns = req.keys()).to_string(index=False),
            '-'*80)
        self.writeLog(content)
        ## ---------------------------------------------------------------------       

        
    #----------------------------------------------------------------------
    def close(self):
        """关闭"""
        self.exit()

    #---------------------------------------------------------------------------
    def writeLog(self, content, logLevel = INFO):
        """发出日志"""
        log = VtLogData()
        log.gatewayName = self.gatewayName
        log.logContent = content
        log.logLevel = logLevel
        self.gateway.onLog(log)     

    #---------------------------------------------------------------------------
    def writeError(self, errorID, errorMsg):
        """发出错误"""
        err = VtErrorData()
        err.gatewayName = self.gatewayName
        err.errorID = errorID
        err.errorMsg = errorMsg.decode('gbk')
        self.gateway.onError(err) 
        ## ---------------------------------------------------------------------
        content = u"[错误代码]:%s [提示信息] %s" %(err.errorID, err.errorMsg)
        if globalSetting.LOGIN:
            self.writeLog(content = content, logLevel = ERROR)
