PROJECT(luasocket C)
cmake_minimum_required(VERSION 2.8)


aux_source_directory(./src socket_src)
list(REMOVE_ITEM socket_src ./src/mime.c)
if(WIN32)
	list(REMOVE_ITEM socket_src ./src/serial.c ./src/unix.c ./src/usocket.c)
	add_definitions("-DLUASOCKET_API=__declspec(dllexport)")
	add_definitions("-DMIME_API=__declspec(dllexport)")
else()
	add_definitions("-DLUASOCKET_API=__attribute__((visibility(default)))")
	add_definitions("-DMIME_API=__attribute__((visibility(default)))")
endif(WIN32)
if(MINGW)
	add_definitions(-DLUASOCKET_INET_PTON)
endif()

INCLUDE_DIRECTORIES(${LUAINC})
add_definitions(-D_WIN32_WINNT=0x0501)
add_definitions(-DLUASOCKET_DEBUG)
add_definitions(-DLUA_BUILD_AS_DLL -DLUA_LIB -DLUASOCKET_EXPORTS)

add_library(socket SHARED ${socket_src})
ADD_LIBRARY(mime SHARED ./src/mime.c ./src/compat.c)
set_target_properties(socket PROPERTIES PREFIX "" OUTPUT_NAME core)
set_target_properties(mime PROPERTIES PREFIX "" OUTPUT_NAME core)
TARGET_LINK_LIBRARIES(socket ${LUALIB} wsock32 ws2_32)
TARGET_LINK_LIBRARIES(mime ${LUALIB})

######install
if( NOT CDIR)
	set(CDIR ${CMAKE_BINARY_DIR}/install/cdir)
endif()
if( NOT LDIR)
	set(LDIR ${CMAKE_BINARY_DIR}/install/ldir)
endif()


INSTALL(TARGETS socket RUNTIME DESTINATION ${CDIR}/socket)
INSTALL(TARGETS mime RUNTIME DESTINATION ${CDIR}/mime)
install(DIRECTORY src/ DESTINATION ${LDIR}/socket
        FILES_MATCHING PATTERN "*.lua"
		PATTERN ltn12.lua EXCLUDE 
		PATTERN socket.lua EXCLUDE
		PATTERN mime.lua EXCLUDE)
install(FILES ./src/socket.lua ./src/mime.lua ./src/ltn12.lua DESTINATION ${LDIR})