Pause::
{
    dt := FormatTime(, "yyyy-MM-dd hh:mm tt")

    ; 한글 오전/오후일 경우 영어로 치환
    if InStr(dt, "오전")
        dt := StrReplace(dt, "오전", "AM")
    else if InStr(dt, "오후")
        dt := StrReplace(dt, "오후", "PM")

    SendText "[" dt "]"
}