#INCLUDE foxcli.h

*-- Los códigos propios de FoxPack, del 10 en adelante (los del 1 al 4 y
*-- el 130 son del host). Se explican en el bloque *!* de la clase.
#DEFINE FP_EXIT_NOT_FOUND     10
#DEFINE FP_EXIT_DOWNLOAD      11
#DEFINE FP_EXIT_CHANGED       12
#DEFINE FP_EXIT_BAD_MANIFEST  13
#DEFINE FP_EXIT_NO_PROJECT    14

*!* FoxPack: libraries for VFP projects, downloaded from GitHub at a fixed version
*!* Libraries are installed into lib\<library>\ of the project and recorded in
*!* foxpack.lock with the exact commit and the SHA-256 of every file. Commit
*!* both to git.
*!* @example foxpack add jsonfox
*!* @exit 10 The library or the version does not exist
*!* @exit 11 Download failed (network, GitHub, a missing file)
*!* @exit 12 A copy in lib\ does not match foxpack.lock
*!* @exit 13 The repository has no valid foxpack.json
*!* @exit 14 The folder is not a project, or foxpack.lock cannot be read
DEFINE CLASS FoxPackCommand AS FoxCliCommand OF foxcli.prg OLEPUBLIC

    *!* Install a library into lib\ and record it in foxpack.lock
    *!* Without a version, the latest tag of the repository. A repository that
    *!* is not in the index (github:user/repo) is installed only after you
    *!* confirm it.
    *!* @tcLibrary <>        jsonfox, jsonfox@13.1 or github:user/repo
    *!* @tcProject -p =.     Project folder
    *!* @tlYes     -y        Confirm without asking (for scripts)
    *!* @example foxpack add jsonfox@13.1
    *!* @example foxpack add github:user/mylib --yes
    PROCEDURE Add(tcLibrary AS String, tcProject AS String, tlYes AS Logical)
        RETURN THIS.TodaviaNo("add")
    ENDPROC


    *!* Download exactly what foxpack.lock says
    *!* For a fresh clone, or to repair a damaged copy.
    *!* @tcProject -p =.     Project folder
    PROCEDURE Restore(tcProject AS String)
        RETURN THIS.TodaviaNo("restore")
    ENDPROC


    *!* Move one library (or all of them) to its latest version
    *!* @tcLibrary <> =      The library; without it, all of them
    *!* @tcProject -p =.     Project folder
    *!* @tlForce   -f        Overwrite a copy that someone has changed
    PROCEDURE Update(tcLibrary AS String, tcProject AS String, tlForce AS Logical)
        RETURN THIS.TodaviaNo("update")
    ENDPROC


    *!* Remove a library from lib\ and from foxpack.lock
    *!* @tcLibrary <>        The library
    *!* @tcProject -p =.     Project folder
    PROCEDURE Remove(tcLibrary AS String, tcProject AS String)
        RETURN THIS.TodaviaNo("remove")
    ENDPROC


    *!* List the installed libraries, with version and commit
    *!* @tcProject -p =.     Project folder
    *!* @example foxpack list
    *!* @example foxpack list --format json
    PROCEDURE List(tcProject AS String)
        LOCAL lcCarpeta, loCandado, loLib, lnI, lcJson

        lcCarpeta = THIS.Carpeta(tcProject)
        IF EMPTY(lcCarpeta)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF
        loCandado = THIS.LeerCandado(lcCarpeta)
        IF ISNULL(loCandado)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF

        IF Console.IsJson()
            lcJson = ""
            FOR lnI = 1 TO loCandado.oLibrerias.Count
                loLib = loCandado.oLibrerias.Item(lnI)
                lcJson = lcJson + IIF(lnI > 1, ",", "") + ;
                    '{"name":"' + Console.JsonEscape(loLib.cNombre) + ;
                    '","version":"' + Console.JsonEscape(loLib.cVersion) + ;
                    '","repo":"' + Console.JsonEscape(loLib.cRepo) + ;
                    '","commit":"' + Console.JsonEscape(loLib.cCommit) + ;
                    '","files":' + TRANSFORM(loLib.oFicheros.Count) + '}'
            ENDFOR
            Console.WriteLine('{"libraries":[' + lcJson + ']}')
            RETURN EXIT_OK
        ENDIF

        IF loCandado.oLibrerias.Count = 0
            Console.WriteLine("No libraries installed in " + lcCarpeta)
            RETURN EXIT_OK
        ENDIF
        FOR lnI = 1 TO loCandado.oLibrerias.Count
            loLib = loCandado.oLibrerias.Item(lnI)
            Console.WriteLine(PADR(loLib.cNombre, 20) + " " + PADR(loLib.cVersion, 10) + " " + ;
                PADR(loLib.cRepo, 30) + " " + LEFT(loLib.cCommit, 7))
        ENDFOR
        RETURN EXIT_OK
    ENDPROC


    *!* Check that the copies in lib\ are the ones in foxpack.lock
    *!* A library's copy is never edited: the fix goes to its repository.
    *!* This command is what watches for it.
    *!* @tcProject -p =.     Project folder
    *!* @exit 12 Some copies differ: it says which ones
    PROCEDURE Verify(tcProject AS String)
        LOCAL lcCarpeta, loCandado, loLib, loFich, loHuella, lnI, lnJ
        LOCAL lcRuta, lcSha, lcEstado, lnMal, lnTotal, lcJson

        lcCarpeta = THIS.Carpeta(tcProject)
        IF EMPTY(lcCarpeta)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF
        loCandado = THIS.LeerCandado(lcCarpeta)
        IF ISNULL(loCandado)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF

        loHuella = NEWOBJECT("Huella", "huella.prg")
        lnMal = 0
        lnTotal = 0
        lcJson = ""
        FOR lnI = 1 TO loCandado.oLibrerias.Count
            loLib = loCandado.oLibrerias.Item(lnI)
            FOR lnJ = 1 TO loLib.oFicheros.Count
                loFich = loLib.oFicheros.Item(lnJ)
                lnTotal = lnTotal + 1
                lcRuta = lcCarpeta + "lib\" + loLib.cNombre + "\" + CHRTRAN(loFich.cRuta, "/", "\")
                lcSha = loHuella.DeFichero(lcRuta)
                DO CASE
                CASE EMPTY(lcSha)
                    lcEstado = "missing"
                CASE lcSha == loFich.cSha256
                    lcEstado = "ok"
                OTHERWISE
                    lcEstado = "changed"
                ENDCASE
                IF !(lcEstado == "ok")
                    lnMal = lnMal + 1
                ENDIF
                IF Console.IsJson()
                    lcJson = lcJson + IIF(lnTotal > 1, ",", "") + ;
                        '{"library":"' + Console.JsonEscape(loLib.cNombre) + ;
                        '","path":"' + Console.JsonEscape(loFich.cRuta) + ;
                        '","status":"' + lcEstado + '"}'
                ELSE
                    IF !(lcEstado == "ok")
                        Console.WriteLine(PADR(lcEstado, 8) + " lib\" + loLib.cNombre + "\" + loFich.cRuta)
                    ENDIF
                ENDIF
            ENDFOR
        ENDFOR

        IF Console.IsJson()
            Console.WriteLine('{"files":[' + lcJson + '],"differ":' + TRANSFORM(lnMal) + '}')
        ELSE
            IF lnMal = 0
                Console.WriteLine(TRANSFORM(lnTotal) + " file(s) checked: all match foxpack.lock")
            ELSE
                Console.Error(TRANSFORM(lnMal) + " of " + TRANSFORM(lnTotal) + ;
                    " file(s) differ from foxpack.lock. A library's copy is never edited: " + ;
                    "fix it in its repository, or run 'foxpack restore' to put the original back.")
            ENDIF
        ENDIF
        RETURN IIF(lnMal = 0, EXIT_OK, FP_EXIT_CHANGED)
    ENDPROC


    *-- La carpeta del proyecto, completa y con la barra final; vacía (y el
    *-- error ya escrito) si no existe.
    PROTECTED FUNCTION Carpeta(tcProject)
        LOCAL lcCarpeta
        lcCarpeta = ADDBS(FULLPATH(EVL(tcProject, ".")))
        IF !DIRECTORY(lcCarpeta)
            Console.Error("foxpack: the project folder does not exist: " + lcCarpeta)
            RETURN ""
        ENDIF
        RETURN lcCarpeta
    ENDFUNC


    *-- El candado del proyecto; .NULL. (y el error ya escrito) si existe y
    *-- no se puede leer. Si no existe, uno vacío.
    PROTECTED FUNCTION LeerCandado(tcCarpeta)
        LOCAL loCandado
        loCandado = NEWOBJECT("Candado", "candado.prg")
        IF !loCandado.Leer(tcCarpeta + "foxpack.lock")
            Console.Error("foxpack: " + loCandado.cFallo)
            RETURN .NULL.
        ENDIF
        RETURN loCandado
    ENDFUNC


    *-- Los comandos de las fases que faltan.
    PROTECTED FUNCTION TodaviaNo(tcComando)
        Console.Error("foxpack: '" + tcComando + "' is not available yet in this build")
        RETURN EXIT_FAILED
    ENDFUNC

ENDDEFINE
