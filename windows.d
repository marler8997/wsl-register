module windows;

import core.sys.windows.windows : DWORD, HRESULT, GetLastError;

wchar[] toWcharCStr(const(char)[] str)
{
    auto buffer = new wchar[str.length + 1];
    foreach (i; 0 .. str.length)
    {
        buffer[i] = str[i];
    }
    buffer[str.length] = '\0';
    return buffer[0 .. str.length];
}
wchar[] toWcharCStr(const(wchar)[] str)
{
    auto buffer = new wchar[str.length + 1];
    buffer[0 .. str.length] = str[];
    buffer[str.length] = '\0';
    return buffer[0 .. str.length];
}

bool putSysError(Writer)(DWORD code, Writer w, /*WORD*/int langId = 0)
{
    import std.string : strip;
    import core.sys.windows.windows :
        FORMAT_MESSAGE_ALLOCATE_BUFFER, FORMAT_MESSAGE_FROM_SYSTEM,
        FORMAT_MESSAGE_IGNORE_INSERTS,
        FormatMessageA, LocalFree;

    char *lpMsgBuf = null;
    const res = FormatMessageA(
        FORMAT_MESSAGE_ALLOCATE_BUFFER |
        FORMAT_MESSAGE_FROM_SYSTEM |
        FORMAT_MESSAGE_IGNORE_INSERTS,
        null,
        code,
        langId,
        cast(char*)&lpMsgBuf,
        0,
        null);
    scope(exit) if (lpMsgBuf) LocalFree(lpMsgBuf);

    if (!lpMsgBuf)
        return false; // fail

    w.put(lpMsgBuf[0 .. res].strip());
    return true; // success
}

auto formatSysError(DWORD lastError = GetLastError())
{
    static struct Formatter
    {
        DWORD lastError;
        void toString(scope void delegate(const(char)[]) sink)
        {
            import std.format : formattedWrite;
            static struct Writer
            {
                void delegate(const(char)[]) sink;
                void put(const(char)[] str) { sink(str); }
            }
            putSysError(lastError, Writer(sink));
            formattedWrite(sink, " (%s)", lastError);
        }
    }
    return Formatter(lastError);
}
auto formatHresultError(HRESULT result)
{
    static struct Formatter
    {
        HRESULT result;
        void toString(scope void delegate(const(char)[]) sink)
        {
            import std.format : formattedWrite;
            static struct Writer
            {
                void delegate(const(char)[]) sink;
                void put(const(char)[] str) { sink(str); }
            }
            putSysError(result, Writer(sink));
            formattedWrite(sink, " (0x%08x)", result);
        }
    }
    return Formatter(result);
}