#!/bin/bash
## 清理原来的 .c .so 文件

## =============================================================================
# rm -f ./*.c
rm -f ./*.so

# rm -f ./app/ctaStrategy/*.c
rm -f ./app/ctaStrategy/*.so

# rm -f ./app/ctaStrategy/*.c
rm -f ./app/ctaStrategy/strategy/*.so

# rm -f ./app/dataRecorder/*.c
rm -f ./app/dataRecorder/*.so

# rm -f ./app/riskManager/*.c
rm -f ./app/riskManager/*.so

# rm -f ./gateway/ctpGateway/*.c
rm -f ./gateway/ctpGateway/*.so

# rm -f ./gateway/ctpGatewayRecorder/*.c
rm -f ./gateway/ctpGatewayRecorder/*.so
## =============================================================================


## =============================================================================
python setup.py build_ext --inplace
## =============================================================================


## =============================================================================
rm -rf ./build
rm -rf ./app/**/build
rm -rf ./gateway/**/build
rm -rf ../event/**/build
## =============================================================================


## =============================================================================
rm -f ./*.c
rm -f ./*.so

rm -f ./app/ctaStrategy/*.c
rm -f ./app/ctaStrategy/*.so

rm -f ./app/ctaStrategy/strategy/*.c
rm -f ./app/ctaStrategy/strategy/*.so

rm -f ./app/dataRecorder/*.c
rm -f ./app/dataRecorder/*.so

rm -f ./app/riskManager/*.c
rm -f ./app/riskManager/*.so

rm -f ./gateway/ctpGateway/*.c
rm -f ./gateway/ctpGateway/*.so

rm -f ./gateway/ctpGatewayRecorder/*.c
rm -f ./gateway/ctpGatewayRecorder/*.so
## =============================================================================
