import sdl2_nim/sdl, sdl2_nim/sdl_image as img, netty, std/[threadpool,
    strutils, os]

const
  Title = "Pong Game"
  ScreenW = 640 #Window width
  ScreenH = 480 #Window height
  WindowFlags = 0

  #RendererFlags = hardware acceleration or Vsync
    #(syncronizing the Present/current frame with the refresh rate)
  RendererFlags = sdl.RendererAccelerated or sdl.RendererPresentVsync

type
  App = ref AppObj #Pointer to AppObj below
  AppObj = object
    window: sdl.Window     #Window pointer
    renderer: sdl.Renderer #Rendering state pointer
                           #sdl.Renderer is the object from SDL that will be
                           #responsible for drawing our image to the screen inside the window

  Image = ref ImageObj
  ImageObj = object of RootObj
    #Image texture(this is what we call an image stored in the memory)
    texture: sdl.Texture
    w, h: int # Image dimensions

####################
# IMAGE PROCEDURES #
####################

#This creates/initializes a new empty Image object
proc newImage(): Image = Image(texture: nil, w: 0, h: 0)

#This frees the given Image object of it's texture -> you should always clean after yourself
proc free(obj: Image) = sdl.destroyTexture(obj.texture)

#Procedure to load an image from a file
#Return true on success or false, if image can't be loaded
proc load(obj: Image, renderer: sdl.Renderer, file: string): bool =
  result = true

  #Load texture from file
  obj.texture = renderer.loadTexture(file)

  if obj.texture == nil: #nil -> nothing -> no image -> error
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't load image %s: %s",
                    file, img.getError())
    return false #Failed to load the image

  #Getting/retrieving image dimensions
  var w, h: cint #cint for interfacing with a C library

  #Getting/retrieving a "texture"'s width and height
  if obj.texture.queryTexture(nil, nil, addr(w), addr(h)) != 0:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't get texture attributes: %s",
                    sdl.getError())
    sdl.destroyTexture(obj.texture)
    return false

  #Here we give our "obj" object the width and height we retrieved above
  obj.w = w
  obj.h = h

#Rendering the texture onto the screen
proc render(obj: Image, renderer: sdl.Renderer, x, y: int): bool =
  #Rendering/drawing rectangle
  var rect = sdl.Rect(x: x, y: y, w: obj.w, h: obj.h)

  #Rendering our image by rendering a copy of it
  if renderer.renderCopy(obj.texture, nil, addr(rect)) == 0: #Error checking
    return true #Texture rendered succesfully
  else:
    return false #Failed rendering

##################################
# SDL boilerplate/necessary code #
##################################

#SDL initialization -> boilerplate code necessary for every SDL application
proc init(app: App): bool =
  #Initialize video AND timer, with error checking and logging
  if sdl.init(sdl.InitVideo or sdl.InitTimer) != 0:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't initialize SDL: %s",
                    sdl.getError())
    return false #This will exit "init" proc and terminate the program

  #Initialize/load SDL_Image dll shared library's .png format image support
  if img.init(img.InitPng) == 0:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't initialize SDL_Image: %s",
                    img.getError())

  #Creating our window(in windowed mode(default) -> you can see the borders)
  app.window = sdl.createWindow(
    Title,
    sdl.WindowPosUndefined,
    sdl.WindowPosUndefined,
    ScreenW,
    ScreenH,
    WindowFlags)

  #Error checking for our window
  if app.window == nil:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't create window: %s",
                    sdl.getError())
    return false #On fail terminate the program

  #Creating the renderer that will draw/render our image
  app.renderer = sdl.createRenderer(app.window, -1, RendererFlags)

  #Error checking for the renderer
  if app.renderer == nil:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't create renderer: %s",
                    sdl.getError())
    return false #On fail terminate the program

  #Setting the draw color to black with error checking(colors and alpha must be in hexadecimal system)
  if app.renderer.setRenderDrawColor(0x00, 0x00, 0x00, 0xFF) != 0:
    sdl.logWarn(sdl.LogCategoryVideo,
                "Can't set draw color: %s",
                sdl.getError())
    return false #On fail terminate the program

  sdl.logInfo(sdl.LogCategoryApplication, "SDL initialized successfully")
  return true

#Shutdown proc(cleanup)
proc exit(app: App) =
  app.renderer.destroyRenderer()
  app.window.destroyWindow()
  img.quit()
  sdl.logInfo(sdl.LogCategoryApplication, "SDL shutdown completed")
  sdl.quit()

##############################
# EVENTS/EVENT HANDLING PROC #
##############################

#PARAMETERS: a changable(var keyword) sequence of sdl.Keycode type(raw input)
proc events(pressed: var seq[sdl.Keycode]): bool =
  result = false

  var e: sdl.Event #Variable to store an sdl.Event type data

  if pressed.len > 0: #if pressed.len > 0, then we have pressed a key
    pressed = @[] #Clearing the event sequence of any previous events

  #Process the keys(events) if any
  while sdl.pollEvent(addr(e)) != 0:
    #Pressing the window's X button
    if e.kind == sdl.Quit:
      return true #Terminate the program

    #If key pressed down, add it to the sequence
    elif e.kind == sdl.KeyDown:
      pressed.add(e.key.keysym.sym) #e.rawKey -> .keysym(lookup table).sym(to get the processed key)

    #Exit on ESC/Escape key press
      if e.key.keysym.sym == sdl.K_Escape:
        return true #Terminate

func inBoundCheck(refX1, refY1, refX2, refY2, sampleX, sampleY: int): bool =
  if sampleX > refX1 and sampleX < refX2 and
    sampleY > refY1 and sampleY < refY2: return true

proc gameServer(): bool =
  var server = newReactor("192.168.50.107", 2001)
  while true:
    server.tick()
    for connection in server.newConnections:
      echo "[new] ", connection.address
    for connection in server.deadConnections:
      echo "[dead] ", connection.address
    for msg in server.messages:
      # need to find a better way to handle nothing...probably not sending (char(8)) in client
      #if len(msg.data) == 0: continue
      if msg.data == "ping": continue
      echo "[msg]", msg.data
      # send msg data to all connections
      for connection in server.connections:
        if connection != msg.conn: server.send(connection, msg.data)

proc keepAliveTimer(): string =
  sleep(9900)
  return "ping"

#proc gameClient(gameMessage: string): bool =


type
  Player = enum player1, player2
  CurrentView = enum title, game, win, lose
  ConnectPressed = enum connectNotPressed, connectPressed
  HostPressed = enum hostNotPressed, hostPressed

template cleanLoad(variableName: untyped, location: string) =
  #Load the images, if not turn off the program
  var variableName {.inject.} = newImage()
  if not variableName.load(app.renderer, location):
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't load image: %s",
                    img.getError())
    done = true #No error -> proceed

template keyboardUp(paddle: Player) =
  if paddle == player1:
    paddle1Pos.y -= paddle1Spd * delta
    if paddle1Pos.y.int < paddle1.h div 2: paddle1Pos.y = float64(
        paddle1.h div 2)
    client.send(connection, "9" & $paddle1Pos.y)
  if paddle == player2:
    paddle2Pos.y -= paddle2Spd * delta
    if paddle2Pos.y.int < paddle2.h div 2: paddle2Pos.y = float64(
        paddle2.h div 2)
    client.send(connection, "9" & $paddle2Pos.y)

template keyboardDown(paddle: Player) =
  if paddle == player1:
    paddle1Pos.y += paddle1Spd * delta
    if paddle1Pos.y.int > ScreenH - (paddle1.h div 2): paddle1Pos.y = float64(
        ScreenH - (paddle1.h div 2))
    client.send(connection, "9" & $paddle1Pos.y)
  if paddle == player2:
    paddle2Pos.y += paddle2Spd * delta
    if paddle2Pos.y.int > ScreenH - (paddle2.h div 2): paddle2Pos.y = float64(
        ScreenH - (paddle2.h div 2))
    client.send(connection, "9" & $paddle2Pos.y)

template moveBall(localPaddle: Player) =
  ballPos.x -= ballSpd * delta * ballDirectionX
  if localPaddle == player1:
    if ballPos.x.int - ball.w div 2 < paddle1.w:
      ballPos.x = float64(paddle1.w + (ball.w div 2))
      ballDirectionX *= -1
      if ballPos.y + float64(ball.h div 2) > paddle1Pos.y - float64(
        paddle1.h div 2) and
        ballPos.y - float64(ball.h div 2) < paddle1Pos.y + float64(
        paddle1.h div 2):
        if ballPos.y > paddle1Pos.y: ballDirectionY += 1
        if ballPos.y < paddle1Pos.y: ballDirectionY -= 1
        ballSpd += 10
        #send info to server
        client.send(connection, "4" & $ballPos.x)
        client.send(connection, "5" & $ballPos.y)
        client.send(connection, "6" & $ballSpd)
        client.send(connection, "7" & $ballDirectionX)
        client.send(connection, "8" & $ballDirectionY)
      else:
        currentView = lose
        #send info to server
        client.send(connection, "3")
  if localPaddle == player2:
    if ballPos.x.int + ball.w div 2 > ScreenW - paddle2.w:
      ballPos.x = float64(ScreenW - paddle2.w - (ball.w div 2))
      ballDirectionX *= -1
      if ballPos.y + float64(ball.h div 2) > paddle2Pos.y - float64(
        paddle2.h div 2) and
        ballPos.y - float64(ball.h div 2) < paddle2Pos.y + float64(
        paddle2.h div 2):
        if ballPos.y > paddle2Pos.y: ballDirectionY += 1
        if ballPos.y < paddle2Pos.y: ballDirectionY -= 1
        ballSpd += 10
        #send info to server
        client.send(connection, "4" & $ballPos.x)
        client.send(connection, "5" & $ballPos.y)
        client.send(connection, "6" & $ballSpd)
        client.send(connection, "7" & $ballDirectionX)
        client.send(connection, "8" & $ballDirectionY)
      else:
        currentView = lose
        #send info to server
        client.send(connection, "3")
  ballPos.y += ballDirectionY
  if ballPos.y < float64(ball.h div 2):
    ballDirectionY *= -1
    ballPos.y += ballDirectionY
  if ballPos.y > ScreenH - float64(ball.h div 2):
    ballDirectionY *= -1
    ballPos.y += ballDirectionY

template renderTitleScreen() =
  discard logo.render(app.renderer, 0, 20)
  if hostButton == hostNotPressed: discard host.render(app.renderer, 100, 200)
  if hostButton == hostPressed: discard hosting.render(app.renderer, 100, 200)
  if connectButton == connectNotPressed: discard connectB.render(app.renderer,
      100, 300)
  if connectButton == connectPressed: discard connecting.render(app.renderer,
      100, 300)

template renderLoseScreen() =
  discard loser.render(app.renderer, 0, 100)

template renderWinScreen() =
  discard winner.render(app.renderer, 0, 100)

template renderGameScreen() =
  discard ball.render(app.renderer,
                      ballPos.x.int - ball.w div 2,
                      ballPos.y.int - ball.h div 2)
  discard paddle1.render(app.renderer,
                      paddle1Pos.x.int - paddle1.w div 2,
                      paddle1Pos.y.int - paddle1.h div 2)
  discard paddle2.render(app.renderer,
                      paddle2Pos.x.int - paddle2.w div 2,
                      paddle2Pos.y.int - paddle2.h div 2)

template titleMouseCLick() =
  sdl.pumpEvents()
  mouseClick = sdl.getMouseState(addr(mouseX), addr(mouseY))
  if not titleSelectionMade:
    if (mouseClick and sdl.button(BUTTON_LEFT)) > 0:
      if inBoundCheck(100, 200, 272, 289, mouseX.int, mouseY.int):
        hostButton = hostPressed
        connectButton = connectNotPressed
        titleSelectionMade = true
        localplayer = player1
        discard spawn gameServer()
        keepAlive = spawn keepAliveTimer()
      if inBoundCheck(100, 300, 402, 389, mouseX.int, mouseY.int):
        connectButton = connectPressed
        hostButton = hostNotPressed
        titleSelectionMade = true
        localPlayer = player2
        keepAlive = spawn keepAliveTimer()
        client.send(connection, "1")
        currentView = game

template resetGameState() =
  paddle1Pos = (float64(10), float64(ScreenH div 2))
  paddle2Pos = (float64(ScreenW - (paddle2.w div 2)), float64(ScreenH div 2))
  ballPos = (float64(ScreenW div 2), float64(ScreenH div 2))
  ballSpd = 200.0 #pixels per second
  ballDirectionX = 1 # angle ball is traveling?
  ballDirectionY = 0 # angle ball is traveling?

template setPaddlePos(localPlayer: Player, val: float) =
  if localPlayer == player1:
    paddle2Pos.y = val.float64
  if localPlayer == player2:
    paddle1Pos.y = val.float64

template incrementClient() =
  client.tick()
  if titleSelectionMade:
    if keepAlive.isReady():
      client.send(connection, ^keepAlive)
      keepAlive = spawn keepAliveTimer()

  for msg in client.messages:
    case msg.data[0]:
    of '1':
      currentView = game
      resetGameState()
    of '2':
      currentView = lose
    of '3':
      currentView = win
    of '4': #get ball X
      ballPos.x = parsefloat(msg.data[1..<len(msg.data)])
    of '5': #get ball y
      ballPos.y = parsefloat(msg.data[1..<len(msg.data)])
    of '6': #get ball speed
      ballSpd = parsefloat(msg.data[1..<len(msg.data)])
    of '7': #get ball direction x
      ballDirectionX = parsefloat(msg.data[1..<len(msg.data)])
    of '8': #get ball direction y
      ballDirectionY = parsefloat(msg.data[1..<len(msg.data)])
    of '9': #get paddle y
      setPaddlePos(localPlayer, parsefloat(msg.data[1..<len(msg.data)]))
    of '0':
      done = true
    else:
      discard


################
# MAIN PROGRAM #
################
proc main() =
  var
    app = App(window: nil, renderer: nil)
    done = false                    #Main loop exit condition
    pressed: seq[sdl.Keycode] = @[] #Pressed keys

  if init(app):
    #Here we load our images, and give it parameters

    cleanLoad(paddle1, "img/paddle 20x120.png")
    cleanLoad(paddle2, "img/paddle 20x120.png")
    cleanLoad(ball, "img/ball 40x40.png")
    cleanLoad(logo, "img/2 Player Pong 640x124.png")
    cleanLoad(connectB, "img/Connect 302x89.png")
    cleanLoad(connecting, "img/Connecting 302x89.png")
    cleanLoad(host, "img/Host 172x89.png")
    cleanLoad(hosting, "img/Hosting 172x89.png")
    cleanLoad(loser, "img/Loser 588x206.png")
    cleanLoad(winner, "img/Winner 640x188.png")

    var
      #paddle1 = newImage() #new empty image
      paddle1Pos: tuple[x, y: float64] = (float64(10), float64(ScreenH div 2))
      paddle1Spd = 400.0          #pixels per second
      paddle2Pos: tuple[x, y: float64] = (float64(ScreenW - (paddle2.w div 2)),
          float64(ScreenH div 2))
      paddle2Spd = 400.0          #pixels per second
      ballPos: tuple[x, y: float64] = (float64(ScreenW div 2), float64(ScreenH div 2))
      ballSpd = 200.0             #pixels per second
      delta = 0.0                 #Time passed since last frame in seconds(float is required)
      ticks: uint64               #Ticks counter - empty for now
                                  #Gets us the high performance counter frequency
                                  #or in other words, the speed our processor is running at
      freq = sdl.getPerformanceFrequency()
      ballDirectionX: float64 = 1 # angle ball is traveling?
      ballDirectionY: float64 = 0 # angle ball is traveling?
      currentView: CurrentView = title
      hostButton: HostPressed = hostNotPressed
      connectButton: ConnectPressed = connectNotPressed
      localPlayer: Player = player1
      mouseX: cint
      mouseY: cint
      mouseClick = sdl.getMouseState(addr(mouseX), addr(mouseY))
      titleSelectionMade: bool = false
      client = newReactor()
      connection = client.connect("192.168.50.107", 2001)
      keepAlive: FlowVar[system.string]

    ######################
    # START OF RENDERING #
    ######################
    ticks = getPerformanceCounter()

    #Main loop
    while not done: #if done = false -> we had an error -> terminate

      #Clear screen with draw color
      discard app.renderer.setRenderDrawColor(0x00, 0x00, 0x00,
          0xFF) #returns "true" or "false"
      if app.renderer.renderClear() != 0: #Clearing the screen with black color with error checking
        sdl.logWarn(sdl.LogCategoryVideo,
                    "Can't clear screen: %s",
                    sdl.getError())

      #Here we render/draw our images
      case currentView:
      of title:
        renderTitleScreen()
        #check for mouse clicks
        titleMouseCLick()
      of lose:
        renderLoseScreen()
        #start newgame on enter from player1

      of win:
        renderWinScreen()
        #start newgame on enter from player1

      of game:
        renderGameScreen()

      #Presenting/drawing the changes we have made
      app.renderer.renderPresent()

      #Event handling - Key proccessing
        #if done = false -> we pressed X button or ESC -> exit
      done = events(pressed)

      #Calculating the delta(frame duration)
      delta = (sdl.getPerformanceCounter() - ticks).float / freq.float

      #Capturing the high performance counter for usage on the next main loop run
      ticks = sdl.getPerformanceCounter()

      #continue server connection
      incrementClient()

      #Get a snapshot of the current state of the keyboard.
      let kbd = sdl.getKeyboardState(nil)

      #Image movement with arrow keys and bounding and controls
      if kbd[ScancodeReturn] > 0:
        if currentView == win or currentView == lose:
          resetGameState()
          currentView = game
          client.send(connection, "1")
      if kbd[ScancodeUp] > 0: keyboardUp(localPlayer)
      if kbd[ScancodeDown] > 0: keyboardDown(localPlayer)

      moveBall(localPlayer)

    #Once the game loop is done we free our image's memory
      #to prevent memory leaks etc
    free(paddle1)
    free(paddle2)
    free(ball)
    free(logo)
    free(connectB)
    free(connecting)
    free(host)
    free(hosting)
    free(loser)
    free(winner)
  exit(app)

#If we press the X button on the SDL window, Escape button
  #or something goes wrong we end up here, and we cleanup after ourselves

main()
