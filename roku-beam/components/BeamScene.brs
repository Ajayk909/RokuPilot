sub init()
    m.video = m.top.findNode("video")
    m.title = m.top.findNode("title")
    m.hint = m.top.findNode("hint")
    m.video.observeField("state", "onState")
    m.top.setFocus(true)
end sub

sub onRequest()
    req = m.top.request
    if req = invalid then return
    if req.url = invalid then return

    url = req.url
    if Left(url, 4) <> "http"
        url = CreateObject("roUrlTransfer").Unescape(url)
    end if

    title = "Beamed video"
    if req.title <> invalid
        if req.title <> "" then title = req.title
    end if

    content = CreateObject("roSGNode", "ContentNode")
    content.url = url
    content.title = title
    content.streamFormat = guessFormat(url)

    m.title.text = title
    m.hint.text = "Loading..."
    m.video.control = "stop"
    m.video.content = content
    m.video.visible = true
    m.video.control = "play"
    m.video.setFocus(true)
end sub

function guessFormat(url as String) as String
    l = LCase(url)
    if Instr(1, l, ".m3u8") > 0 then return "hls"
    if Instr(1, l, ".mpd") > 0 then return "dash"
    return "mp4"
end function

sub showIdle(message as String)
    m.video.visible = false
    m.hint.text = message
    m.top.setFocus(true)
end sub

sub onState()
    s = m.video.state
    if s = "error"
        showIdle("Couldn't play that link (" + m.video.errorMsg + ")")
    else if s = "finished"
        showIdle("Finished. Send another link anytime.")
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if press and key = "back" and m.video.visible
        m.video.control = "stop"
        showIdle("Stopped. Send another link anytime.")
        return true
    end if
    return false
end function
