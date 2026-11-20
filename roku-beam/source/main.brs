' Beam - plays whatever link your phone/laptop sends.
' Launched with:  POST http://<roku>:8060/launch/dev?url=<link>&title=<name>
' While open:     POST http://<roku>:8060/input?url=<link>&title=<name>

sub Main(args as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("BeamScene")
    screen.Show()

    input = CreateObject("roInput")
    input.SetMessagePort(port)

    if args.url <> invalid then scene.request = args

    while true
        msg = wait(0, port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent"
            if msg.IsScreenClosed() then return
        else if msgType = "roInputEvent"
            info = msg.GetInfo()
            if info <> invalid
                if info.url <> invalid then scene.request = info
            end if
        end if
    end while
end sub
