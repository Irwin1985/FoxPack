*==================================================================
* foxcli.h -- the exit codes of foxpack
*
* What a command RETURNS is the process exit code: what whoever calls
* the CLI from a script reads (%ERRORLEVEL%, $LASTEXITCODE). To SHOW a
* result, write it with Console.WriteLine(); RETURN is only the code.
*
* 2 to 4 and 130 belong to the host: do not return them.
*    2  malformed invocation         3  the component could not start
*    4  internal host failure      130  cancelled with Ctrl+C
*
* Yours run from 10 to 125. Declare them here, with a name:
*    #DEFINE EXIT_NOT_FOUND  10
* and in the command: RETURN EXIT_NOT_FOUND
*==================================================================

#DEFINE EXIT_OK      0    && all good: same as RETURN .T., or no RETURN at all
#DEFINE EXIT_FAILED  1    && the command failed: same as RETURN .F.
