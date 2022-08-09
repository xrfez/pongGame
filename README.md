# pongGame

2 Player pongGame written as a test of sdl and netcode.  Designed to be played on 2 seperate machines on the network.  Included SDL `.dll` files are `Windows x64`.
The module uses `spawn` to run the server, therefore requires pThreads `.dll`.
IP is hardcoded in 2 locations
`connection = client.connect("192.168.50.107", 2001)` and `var server = newReactor("192.168.50.107", 2001)`

compile with `nim c -d:release --App:gui --threads:on pongGame.nim`
