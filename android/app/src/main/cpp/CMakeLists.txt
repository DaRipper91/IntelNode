cmake_minimum_required(VERSION 3.18.1)
project("native-socket")

# 添加库
add_library(native-socket SHARED native-socket.cpp)

# 16 KB page alignment for Pixel 10 Pro (Android 17, 16k page kernel)
# Without this, LOAD segments use 4 KB alignment and fail to dlopen on 16k devices.
set_target_properties(native-socket PROPERTIES
    LINK_FLAGS "-Wl,-z,max-page-size=0x4000"
)

# 链接日志库
find_library(log-lib log)

# 指定目标属性
target_link_libraries(native-socket ${log-lib})