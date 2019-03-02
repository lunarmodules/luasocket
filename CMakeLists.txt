PROJECT(luasocket C)
cmake_minimum_required(VERSION 2.8)


aux_source_directory(./src socket_src)
list(REMOVE_ITEM socket_src ./src/mime.c)
set(LUASOCKET_LINK)
if(WIN32)
	list(REMOVE_ITEM socket_src ./src/serial.c ./src/unix.c ./src/usocket.c ./src/unixdgram.c ./src/unixstream.c)
	add_definitions(-D_WIN32_WINNT=0x0600) ##should be this or the next two for working on XP
	#add_definitions(-D_WIN32_WINNT=0x0501)
	#add_definitions(-DLUASOCKET_INET_PTON)
	add_definitions("-DLUASOCKET_API=__declspec(dllexport)")
	add_definitions("-DMIME_API=__declspec(dllexport)")
	set(LUASOCKET_LINK  wsock32 ws2_32 )
	set(POSTN dll)
else()
	list(REMOVE_ITEM socket_src ./src/wsocket.c) 
	add_definitions("-DLUASOCKET_API=__attribute__((visibility(default)))")
	add_definitions("-DMIME_API=__attribute__((visibility(default)))")
	set(POSTN so)
endif(WIN32)


INCLUDE_DIRECTORIES(${LUA_INCLUDE_DIR})

add_definitions(-DLUASOCKET_DEBUG)
add_definitions(-DLUA_BUILD_AS_DLL -DLUA_LIB -DLUASOCKET_EXPORTS)

add_library(socket SHARED ${socket_src})
ADD_LIBRARY(mime SHARED ./src/mime.c ./src/compat.c)

if(MSVC)
	set_target_properties(socket PROPERTIES PREFIX "lib")
	set_target_properties(mime PROPERTIES PREFIX "lib")
endif()

TARGET_LINK_LIBRARIES(socket ${LUA_LIBRARY} ${LUASOCKET_LINK} )
TARGET_LINK_LIBRARIES(mime ${LUA_LIBRARY}) 

######install
#set default LDIR and CDIR if not given
if( NOT CDIR)
	set(CDIR .)
endif()
if( NOT LDIR)
	set(LDIR ./lua)
endif()

##cant use set_target_properties to rename because one overwrites the other so:
INSTALL(FILES ${CMAKE_CURRENT_BINARY_DIR}/libsocket.${POSTN} DESTINATION ${CDIR}/socket RENAME core.${POSTN})
INSTALL(FILES ${CMAKE_CURRENT_BINARY_DIR}/libmime.${POSTN} DESTINATION ${CDIR}/mime RENAME core.${POSTN})  

install(DIRECTORY src/ DESTINATION ${LDIR}/socket
        FILES_MATCHING PATTERN "*.lua"
		PATTERN ltn12.lua EXCLUDE 
		PATTERN socket.lua EXCLUDE
		PATTERN mime.lua EXCLUDE)
install(FILES ./src/socket.lua ./src/mime.lua ./src/ltn12.lua DESTINATION ${LDIR})