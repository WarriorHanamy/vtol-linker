from pathlib import Path


path = Path("/root/catkin_ws/src/livox_ros_driver2/CMakeLists.txt")
text = path.read_text()

old = """  if(${CMAKE_SYSTEM_PROCESSOR} STREQUAL "x86_64")
    set(LIVOX_LIDAR_SDK_LIBRARY ${CMAKE_CURRENT_SOURCE_DIR}/livox_sdk/lib/x86_64/liblivox_lidar_sdk_static.a)
  else()
    message(FATAL_ERROR "Unsupported platform: ${CMAKE_SYSTEM_PROCESSOR}")
  endif()
"""

new = """  if(${CMAKE_SYSTEM_PROCESSOR} STREQUAL "x86_64")
    set(LIVOX_LIDAR_SDK_LIBRARY ${CMAKE_CURRENT_SOURCE_DIR}/livox_sdk/lib/x86_64/liblivox_lidar_sdk_static.a)
  elseif(${CMAKE_SYSTEM_PROCESSOR} STREQUAL "aarch64")
    set(LIVOX_LIDAR_SDK_LIBRARY ${CMAKE_CURRENT_SOURCE_DIR}/livox_sdk/lib/aarch64/liblivox_lidar_sdk_static.a)
  else()
    message(FATAL_ERROR "Unsupported platform: ${CMAKE_SYSTEM_PROCESSOR}")
  endif()
"""

if old not in text:
    if new in text:
        raise SystemExit(0)
    raise SystemExit("expected ROS1 platform block not found")

path.write_text(text.replace(old, new, 1))
