*==================================================================
* foxcli.prg -- the base class of the foxpack commands
*
* It belongs to FoxCli: do not change it. Your commands go in main.prg,
* in the class that inherits from this one (AS FoxCliCommand OF
* foxcli.prg). What the host needs in every command lives here:
* THIS.oCon, THIS.oArgs and Console, the short form of THIS.oCon. And,
* since version 3, running a child process with a time limit (ChildRun)
* and a VFP without windows (VfpHeadless). Since version 4, that child
* dies with the CLI, even when the CLI is killed.
*
* When a new version of FoxForge changes it, building (Ctrl+F7) will
* offer to update it. The line below is its version.
*
* FOXCLI-BASE 4
*==================================================================

DEFINE CLASS FoxCliCommand AS Session

    *-- The host sets these before calling each command.
    oCon  = .NULL.
    oArgs = .NULL.

    *-- What the last call to ChildRun left (and to VfpHeadless, which uses
    *-- it): the child's PID, its exit code (-1 if it did not finish by
    *-- itself) and the text of the window it had open when it had to be
    *-- killed, for instance "Locate File: Unable to find ...". cVfpTried, the
    *-- paths VfpResolve looked at without finding VFP, one per line.
    *-- PROTECTED, like the methods below: FoxCli publishes as a command
    *-- everything public in the class, and this is not a command.
    *-- cChildJob: empty if ChildRun's last child went into its Job (it dies
    *-- with the CLI); otherwise, why not. cVfpTemp: the folder VfpHeadless
    *-- keeps when the result is not "ok" (empty when it was), to cite or delete it.
    PROTECTED nChildPid, nChildExit, cChildDialog, cVfpTried, cChildJob, cVfpTemp
    nChildPid = 0
    nChildExit = -1
    cChildDialog = ""
    cVfpTried = ""
    cChildJob = ""
    cVfpTemp = ""

    *-- Console is THIS.oCon with a short name: Console.WriteLine("Hello")
    *-- is THIS.oCon.WriteLine("Hello"), with the same methods. It works
    *-- across the whole program, a loose PROCEDURE or another class too.
    *--
    *-- It is born here: the host sets oCon before calling the command,
    *-- and this assign publishes it. PUBLIC and not PRIVATE because the
    *-- host calls the command directly, with no VFP code in front that
    *-- could declare a PRIVATE; every run of the CLI is a new process, so
    *-- nothing is left hanging (and under MCP AfterCommand releases it, and the
    *-- host sets it again with oCon). Do not declare another LOCAL Console: it
    *-- would hide this one in that method.
    PROTECTED PROCEDURE oCon_Assign(toCon)
        THIS.oCon = toCon
        PUBLIC Console
        Console = toCon
    ENDPROC

    *-- AfterCommand is called by your CLI's MCP server (FoxCli MCP) AFTER
    *-- every call, also when the command failed. The CLI never calls it:
    *-- there every run is a new process. Under MCP, though, this same object
    *-- serves the agent's whole session, and without this a table left open
    *-- or a PUBLIC from one command would still be there in the next. It is
    *-- not a command: FoxCli reserves the name, like Init or Destroy.
    *--
    *-- It closes the tables and cursors of this object's data session (the
    *-- private one) and releases the PUBLIC and PRIVATE variables (Console
    *-- too: the host sets it again with oCon before the next command).
    *--
    *-- It does NOT touch the SET commands or the directory: they are yours,
    *-- and the working directory is the agent's. A SET DELETED ON from one
    *-- command is still on in the next, and so is a CD.
    *--
    *-- If your CLI wants to keep something between calls, override it in your
    *-- class with your own code and DODEFAULT() AS THE LAST LINE. That is the
    *-- trap: CLEAR MEMORY also releases the parameters and local variables of
    *-- the method that runs it, and a line after it that uses a variable fails
    *-- with "Variable not found".
    PROCEDURE AfterCommand
        CLOSE DATABASES ALL
        CLEAR MEMORY
    ENDPROC


    *==============================================================
    * Child processes (FOXCLI-BASE 3)
    *
    * ChildRun starts a process and waits with a time limit; VfpHeadless
    * runs a .prg in a full VFP without windows; VfpResolve finds that VFP.
    * They are PROTECTED: you call them from your commands
    * (THIS.ChildRun(...)), not from the command line.
    *==============================================================

    *-- Starts tcCommandLine HIDDEN (no console window) in the folder tcDir
    *-- (empty = the current one), and waits. Returns:
    *--   "ok:<exit>"     it finished; <exit> is its exit code (THIS.nChildExit)
    *--   "hung"          the time limit ran out: its dialog was read
    *--                   (THIS.cChildDialog) and THAT process was killed, by its
    *--                   handle, never by name
    *--   "cancelled"     Ctrl+C: the child was killed
    *--   "error:<text>"  it did not start
    *-- tnSeconds is the time limit in seconds (0 or none = 60). With
    *-- tcBeatFile, the limit starts over every time that file changes size:
    *-- the child writes a line when each step starts and ends, and the limit
    *-- becomes PER STEP. The child has to CLOSE the file after each line
    *-- (STRTOFILE(..., .T.) does): with the file open, Windows may not publish
    *-- the new size.
    *-- The child inherits the CLI's environment variables. The folder is given
    *-- to the child when it is created, so the CLI's own folder is never
    *-- touched, not even when the launch fails.
    *-- THE CHILD DIES WITH THE CLI (FOXCLI-BASE 4). It is created suspended, put in
    *-- a Windows Job with KILL_ON_JOB_CLOSE and only then started: its own
    *-- children are born inside. The Job is closed when ChildRun returns, or by
    *-- itself when the CLI dies (killed, crashed, Ctrl+C): Windows then kills
    *-- everything in it. So whatever the child left running dies when ChildRun
    *-- returns. Jobs nest since Windows 8, and a CLI already running inside one
    *-- (a terminal, an MCP host) creates its own all the same. If it cannot, the
    *-- child is started anyway: cChildJob says why and a warning goes to stderr.
    PROTECTED FUNCTION ChildRun(tcCommandLine, tcDir, tnSeconds, tcBeatFile)
        LOCAL lcSi, lcPi, lcCmd, lcDir, lnOk, lnProc, lnThread, lcRes, lnPlazo
        LOCAL lnDesde, lnTam, lnTamAntes, lnCode, loErr, lcNombre, loSh, lnJob, lnErr

        THIS.nChildPid = 0
        THIS.nChildExit = -1
        THIS.cChildDialog = ""
        lnPlazo = IIF(VARTYPE(tnSeconds) == "N" AND tnSeconds > 0, tnSeconds, 60) * 1000
        lcDir = IIF(VARTYPE(tcDir) == "C", ALLTRIM(tcDir), "")
        IF EMPTY(lcDir)
            TRY
                loSh = CREATEOBJECT("WScript.Shell")
                lcDir = loSh.CurrentDirectory
            CATCH
                lcDir = SYS(5) + SYS(2003)
            ENDTRY
        ENDIF
        THIS.ChildDeclare()
        lnJob = THIS.ChildJob()

        *-- STARTUPINFO (68 bytes, only cb) and PROCESS_INFORMATION (16 bytes).
        *-- 134217728 = 0x08000000 = CREATE_NO_WINDOW: a console child opens no window.
        lcSi = BINTOC(68, "4RS") + REPLICATE(CHR(0), 64)
        lcPi = REPLICATE(CHR(0), 16)
        lcCmd = tcCommandLine + CHR(0)
        *-- Suspended when there is a Job: it goes in before running anything.
        lnOk = FoxCliCreateProcess(0, @lcCmd, 0, 0, 0, 134217728 + IIF(lnJob = 0, 0, 4), 0, lcDir, @lcSi, @lcPi)
        IF lnOk = 0
            lnErr = FoxCliGetLastError()
            IF lnJob <> 0
                =FoxCliCloseHandle(lnJob)
            ENDIF
            RETURN "error:could not start (Windows error " + TRANSFORM(lnErr) + "): " + tcCommandLine
        ENDIF
        lnProc = CTOBIN(SUBSTR(lcPi, 1, 4), "4RS")
        lnThread = CTOBIN(SUBSTR(lcPi, 5, 4), "4RS")
        THIS.nChildPid = CTOBIN(SUBSTR(lcPi, 9, 4), "4RS")
        IF lnJob <> 0
            IF FoxCliAssignProcessToJobObject(lnJob, lnProc) = 0
                THIS.cChildJob = "the child could not be put in its Job (Windows error " + ;
                    TRANSFORM(FoxCliGetLastError()) + "): it will not die with this CLI"
            ENDIF
            =FoxCliResumeThread(lnThread)
        ENDIF
        =FoxCliCloseHandle(lnThread)
        IF !EMPTY(THIS.cChildJob) AND VARTYPE(THIS.oCon) == "O"
            THIS.oCon.Error("warning: " + THIS.cChildJob)
        ENDIF

        lcRes = ""
        TRY
            lnTamAntes = THIS.ChildBeat(tcBeatFile)
            lnDesde = FoxCliGetTickCount()
            DO WHILE .T.
                *-- The 100 ms wait is on the process itself: it returns early if it ends.
                IF FoxCliWaitForSingleObject(lnProc, 100) = 0
                    lnCode = 0
                    =FoxCliGetExitCodeProcess(lnProc, @lnCode)
                    THIS.nChildExit = IIF(lnCode < 0, lnCode + 4294967296, lnCode)
                    lcRes = "ok:" + TRANSFORM(THIS.nChildExit)
                    EXIT
                ENDIF
                IF VARTYPE(THIS.oCon) == "O" AND THIS.oCon.IsCancelled()
                    =FoxCliTerminateProcess(lnProc, 130)
                    =FoxCliWaitForSingleObject(lnProc, 5000)
                    lcRes = "cancelled"
                    EXIT
                ENDIF
                lnTam = THIS.ChildBeat(tcBeatFile)
                IF lnTam <> lnTamAntes
                    lnTamAntes = lnTam
                    lnDesde = FoxCliGetTickCount()
                ENDIF
                IF THIS.ChildElapsed(lnDesde) > lnPlazo
                    THIS.cChildDialog = THIS.ChildDialog(THIS.nChildPid)
                    =FoxCliTerminateProcess(lnProc, 1)
                    =FoxCliWaitForSingleObject(lnProc, 5000)
                    lcRes = "hung"
                    EXIT
                ENDIF
            ENDDO
        CATCH TO loErr
            =FoxCliTerminateProcess(lnProc, 1)
            lcRes = "error:" + loErr.Message
        FINALLY
            =FoxCliCloseHandle(lnProc)
            IF lnJob <> 0
                =FoxCliCloseHandle(lnJob)
            ENDIF
        ENDTRY
        RETURN lcRes
    ENDFUNC


    PROTECTED PROCEDURE ChildDeclare
        DECLARE INTEGER CreateProcess IN kernel32 AS FoxCliCreateProcess ;
            INTEGER, STRING @, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER, STRING, STRING @, STRING @
        DECLARE INTEGER WaitForSingleObject IN kernel32 AS FoxCliWaitForSingleObject INTEGER, INTEGER
        DECLARE INTEGER GetExitCodeProcess IN kernel32 AS FoxCliGetExitCodeProcess INTEGER, INTEGER @
        DECLARE INTEGER TerminateProcess IN kernel32 AS FoxCliTerminateProcess INTEGER, INTEGER
        DECLARE INTEGER CloseHandle IN kernel32 AS FoxCliCloseHandle INTEGER
        DECLARE INTEGER GetLastError IN kernel32 AS FoxCliGetLastError
        DECLARE INTEGER GetTickCount IN kernel32 AS FoxCliGetTickCount
        DECLARE INTEGER CreateJobObject IN kernel32 AS FoxCliCreateJobObject INTEGER, INTEGER
        DECLARE INTEGER SetInformationJobObject IN kernel32 AS FoxCliSetInformationJobObject INTEGER, INTEGER, STRING @, INTEGER
        DECLARE INTEGER AssignProcessToJobObject IN kernel32 AS FoxCliAssignProcessToJobObject INTEGER, INTEGER
        DECLARE INTEGER ResumeThread IN kernel32 AS FoxCliResumeThread INTEGER
    ENDPROC


    *-- The Job for a child: KILL_ON_JOB_CLOSE, or 0 if it could not be made
    *-- (cChildJob says why). The structure is the 32-bit
    *-- JOBOBJECT_EXTENDED_LIMIT_INFORMATION: 112 bytes, LimitFlags at byte 16 (0x2000).
    PROTECTED FUNCTION ChildJob()
        LOCAL lnJob, lcInfo
        THIS.cChildJob = ""
        lnJob = FoxCliCreateJobObject(0, 0)
        IF lnJob = 0
            THIS.cChildJob = "the Job could not be created (Windows error " + TRANSFORM(FoxCliGetLastError()) + "): the child will not die with this CLI"
            RETURN 0
        ENDIF
        lcInfo = REPLICATE(CHR(0), 16) + BINTOC(8192, "4RS") + REPLICATE(CHR(0), 92)
        IF FoxCliSetInformationJobObject(lnJob, 9, @lcInfo, 112) = 0
            THIS.cChildJob = "KILL_ON_JOB_CLOSE could not be set (Windows error " + TRANSFORM(FoxCliGetLastError()) + "): the child will not die with this CLI"
            =FoxCliCloseHandle(lnJob)
            RETURN 0
        ENDIF
        RETURN lnJob
    ENDFUNC


    *-- The size of the heartbeat file, or -1 if there is none (rule 56: ADIR).
    PROTECTED FUNCTION ChildBeat(tcFile)
        LOCAL ARRAY laF[1]
        IF VARTYPE(tcFile) <> "C" OR EMPTY(tcFile)
            RETURN -1
        ENDIF
        IF ADIR(laF, tcFile, "H") = 0
            RETURN -1
        ENDIF
        RETURN laF[1, 2]
    ENDFUNC


    *-- Milliseconds since tnSince, with GetTickCount. SECONDS() goes back to 0
    *-- at midnight; GetTickCount wraps after 49 days, and the MOD absorbs it.
    PROTECTED FUNCTION ChildElapsed(tnSince)
        RETURN MOD(FoxCliGetTickCount() - tnSince, 4294967296)
    ENDFUNC


    *-- What the visible windows of a process say: their title and their
    *-- static texts, "Locate File: Unable to find ...". It is what a person
    *-- sees in front of a process stuck on a dialog, and what whoever started
    *-- it needs to know why it did not come back. The top-level windows are
    *-- walked (FindWindowEx with parent 0) and those of the PID are kept.
    PROTECTED FUNCTION ChildDialog(tnPid)
        LOCAL lcRes, lnHwnd, lnPid, lnVueltas, lcTitulo, lnHijo, lcClase, lcTexto, loErr, lnLen
        lcRes = ""
        TRY
            DECLARE INTEGER FindWindowEx IN user32 AS FoxCliFindWindowEx INTEGER, INTEGER, INTEGER, INTEGER
            DECLARE INTEGER GetWindowThreadProcessId IN user32 AS FoxCliGetPid INTEGER, INTEGER @
            DECLARE INTEGER GetWindowText IN user32 AS FoxCliGetText INTEGER, STRING @, INTEGER
            DECLARE INTEGER GetClassName IN user32 AS FoxCliGetClass INTEGER, STRING @, INTEGER
            DECLARE INTEGER IsWindowVisible IN user32 AS FoxCliVisible INTEGER
            lnHwnd = 0
            lnVueltas = 0
            DO WHILE lnVueltas < 5000
                lnVueltas = lnVueltas + 1
                lnHwnd = FoxCliFindWindowEx(0, lnHwnd, 0, 0)
                IF lnHwnd = 0
                    EXIT
                ENDIF
                lnPid = 0
                =FoxCliGetPid(lnHwnd, @lnPid)
                IF lnPid <> tnPid OR FoxCliVisible(lnHwnd) = 0
                    LOOP
                ENDIF
                lcTitulo = THIS.ChildWindowText(lnHwnd)
                lcRes = lcRes + IIF(EMPTY(lcRes), "", " / ") + lcTitulo
                lnHijo = 0
                DO WHILE .T.
                    lnHijo = FoxCliFindWindowEx(lnHwnd, lnHijo, 0, 0)
                    IF lnHijo = 0
                        EXIT
                    ENDIF
                    lcClase = SPACE(64)
                    lnLen = FoxCliGetClass(lnHijo, @lcClase, 64)
                    lcClase = LEFT(lcClase, lnLen)
                    lcTexto = THIS.ChildWindowText(lnHijo)
                    IF UPPER(lcClase) == "STATIC" AND !EMPTY(lcTexto)
                        lcRes = lcRes + ": " + lcTexto
                    ENDIF
                ENDDO
            ENDDO
        CATCH TO loErr
            lcRes = lcRes + " (" + loErr.Message + ")"
        ENDTRY
        RETURN ALLTRIM(CHRTRAN(lcRes, CHR(13) + CHR(10), "  "))
    ENDFUNC


    *-- In two steps on purpose (rule 69): in LEFT(lcBuf, Api(@lcBuf, ...))
    *-- VFP evaluates lcBuf BEFORE the call that fills it, and it comes out empty.
    PROTECTED FUNCTION ChildWindowText(tnHwnd)
        LOCAL lcBuf, lnLen
        lcBuf = SPACE(512)
        lnLen = FoxCliGetText(tnHwnd, @lcBuf, 512)
        RETURN ALLTRIM(LEFT(lcBuf, lnLen))
    ENDFUNC


    *-- The path of the full VFP (vfp9.exe, or vfpa.exe if asked for), or ""
    *-- if there is none. tcExplicit (your --vfp, preferably an absolute path)
    *-- and otherwise the environment variable tcEnvVar (for instance
    *-- "FOXCLI_VFP"): if given, they are THE ONLY thing looked at, and they
    *-- have to be an .exe that exists. If not, Program Files (x86 and 64) and
    *-- the VFP 9 folder in the registry. Leaves in THIS.cVfpTried what it
    *-- looked at without finding it.
    PROTECTED FUNCTION VfpResolve(tcExplicit, tcEnvVar)
        LOCAL lcCand, lnI, loShell, lcDir
        LOCAL ARRAY laC[1]

        THIS.cVfpTried = ""
        lcCand = ""
        DO CASE
        CASE VARTYPE(tcExplicit) == "C" AND !EMPTY(tcExplicit)
            lcCand = ALLTRIM(tcExplicit)
        CASE VARTYPE(tcEnvVar) == "C" AND !EMPTY(tcEnvVar) AND !EMPTY(GETENV(tcEnvVar))
            lcCand = GETENV(tcEnvVar)
        ENDCASE
        IF !EMPTY(lcCand)
            IF FILE(lcCand) AND UPPER(JUSTEXT(lcCand)) == "EXE"
                RETURN lcCand
            ENDIF
            THIS.cVfpTried = lcCand + CHR(13)
            RETURN ""
        ENDIF
        lcCand = ADDBS(GETENV("ProgramFiles(x86)")) + "Microsoft Visual FoxPro 9\vfp9.exe" + CHR(13) + ;
                 ADDBS(GETENV("ProgramFiles")) + "Microsoft Visual FoxPro 9\vfp9.exe" + CHR(13)
        lcDir = ""
        TRY
            loShell = CREATEOBJECT("WScript.Shell")
            lcDir = loShell.RegRead("HKLM\SOFTWARE\Microsoft\VisualFoxPro\9.0\Setup\VFP\ProductDir")
        CATCH
            lcDir = ""
        ENDTRY
        IF !EMPTY(lcDir)
            lcCand = lcCand + ADDBS(lcDir) + "vfp9.exe" + CHR(13)
        ENDIF
        FOR lnI = 1 TO ALINES(laC, lcCand, 1 + 4)
            IF FILE(laC[lnI])
                RETURN laC[lnI]
            ENDIF
            THIS.cVfpTried = THIS.cVfpTried + laC[lnI] + CHR(13)
        ENDFOR
        RETURN ""
    ENDFUNC


    *-- Runs tcPrg in a full VFP, hidden, with a time limit. Returns "ok",
    *-- "hung", "cancelled" or "error:<no. message (program, line)>".
    *-- The six conditions of REGLAS-VFP.md section 2 for a loose vfp9.exe:
    *-- the ABSOLUTE path of the .prg, checked; CONFIG.FPW with SCREEN and
    *-- RESOURCE OFF; an ON ERROR that writes and QUITs; no stale .fxp; a time
    *-- limit; and THAT process is killed, never by name. Empty tcVfp =
    *-- VfpResolve("", "FOXCLI_VFP"). tcDir is VFP's folder; tnSeconds and
    *-- tcBeatFile, those of ChildRun. If the result is not "ok", the temporary
    *-- folder stays, to look at it.
    PROTECTED FUNCTION VfpHeadless(tcPrg, tcDir, tnSeconds, tcVfp, tcBeatFile)
        LOCAL lcVfp, lcTmp, lcCfg, lcWrap, lcErrPrg, lcErrOut, lcFxp, lcRes

        THIS.cVfpTemp = ""
        lcVfp = IIF(VARTYPE(tcVfp) == "C" AND !EMPTY(tcVfp), tcVfp, THIS.VfpResolve("", "FOXCLI_VFP"))
        IF EMPTY(lcVfp)
            RETURN "error:vfp9.exe was not found. Tried: " + CHRTRAN(ALLTRIM(THIS.cVfpTried, 1, CHR(13)), CHR(13), "; ")
        ENDIF
        IF VARTYPE(tcPrg) <> "C" OR !FILE(tcPrg)
            RETURN "error:not found: " + TRANSFORM(tcPrg)
        ENDIF

        *-- An .fxp next to its .prg runs even if the .prg is newer.
        lcFxp = FORCEEXT(tcPrg, "fxp")
        IF FILE(lcFxp)
            TRY
                ERASE (lcFxp)
            CATCH
            ENDTRY
        ENDIF

        lcTmp = ADDBS(SYS(2023)) + "foxcli-" + SYS(2015) + "\"
        MD (lcTmp)
        lcCfg = lcTmp + "CONFIG.FPW"
        lcErrPrg = lcTmp + "fcerror.prg"
        lcErrOut = lcTmp + "vfp-error.txt"
        lcWrap = lcTmp + "fcrun.prg"
        STRTOFILE("SCREEN = OFF" + CHR(13) + CHR(10) + "RESOURCE = OFF" + CHR(13) + CHR(10), lcCfg)
        *-- The handler lives in its own .prg, by its path: a program that does
        *-- CLEAR ALL would take a PROCEDURE of this one with it.
        STRTOFILE("LPARAMETERS tnError, tcMessage, tcProgram, tnLine" + CHR(13) + CHR(10) + ;
                  "STRTOFILE(TRANSFORM(tnError) + ' ' + tcMessage + ' (' + tcProgram + ', line ' + " + ;
                  "TRANSFORM(tnLine) + ')', [" + lcErrOut + "])" + CHR(13) + CHR(10) + ;
                  "QUIT" + CHR(13) + CHR(10), lcErrPrg)
        STRTOFILE("_SCREEN.Visible = .F." + CHR(13) + CHR(10) + ;
                  "ON ERROR DO ([" + lcErrPrg + "]) WITH ERROR(), MESSAGE(), PROGRAM(), LINENO()" + CHR(13) + CHR(10) + ;
                  "DO ([" + tcPrg + "])" + CHR(13) + CHR(10) + ;
                  "QUIT" + CHR(13) + CHR(10), lcWrap)

        lcRes = THIS.ChildRun('"' + lcVfp + '" -T -c"' + lcCfg + '" "' + lcWrap + '"', tcDir, tnSeconds, tcBeatFile)
        IF LEFT(lcRes, 3) == "ok:"
            lcRes = IIF(FILE(lcErrOut), "error:" + FILETOSTR(lcErrOut), "ok")
        ENDIF
        IF lcRes == "ok"
            TRY
                ERASE (lcCfg)
                ERASE (lcErrPrg)
                ERASE (lcWrap)
                ERASE (FORCEEXT(lcErrPrg, "fxp"))
                ERASE (FORCEEXT(lcWrap, "fxp"))
                RD (lcTmp)
            CATCH
            ENDTRY
        ELSE
            THIS.cVfpTemp = lcTmp
        ENDIF
        RETURN lcRes
    ENDFUNC

ENDDEFINE
