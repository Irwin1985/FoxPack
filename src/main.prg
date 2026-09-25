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
        LOCAL lcCarpeta, loCandado, lcSpec, lcVersion, lcNombre, lcRepo, llDeGithub, lnPos
        LOCAL loRemoto, loIndice, loEntrada, loEtiquetas, loEtq, loManif, lcTexto
        LOCAL loActual, loInst, loLib, loF, lnI, lcCambios

        lcCarpeta = THIS.Carpeta(tcProject)
        IF EMPTY(lcCarpeta)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF
        loCandado = THIS.LeerCandado(lcCarpeta)
        IF ISNULL(loCandado)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF

        *-- «jsonfox», «jsonfox@13.1», «github:usuario/repo» o
        *-- «github:usuario/repo@1.0». La versión va detrás de la última @.
        lcSpec = ALLTRIM(tcLibrary)
        lcVersion = ""
        lnPos = RAT("@", lcSpec)
        IF lnPos > 0
            lcVersion = ALLTRIM(SUBSTR(lcSpec, lnPos + 1))
            lcSpec = ALLTRIM(LEFT(lcSpec, lnPos - 1))
        ENDIF
        llDeGithub = LOWER(LEFT(lcSpec, 7)) == "github:"
        loRemoto = NEWOBJECT("Remoto", "remoto.prg")

        *-- 1. De qué repo sale.
        IF llDeGithub
            lcRepo = ALLTRIM(SUBSTR(lcSpec, 8))
            IF !loRemoto.RepoValido(lcRepo)
                Console.Error("foxpack: " + loRemoto.cFallo)
                RETURN EXIT_FAILED
            ENDIF
            IF !THIS.Confirmar("'" + lcRepo + "' is not in the FoxPack index. Its code will be " + ;
                    "compiled into your program.", tlYes)
                RETURN EXIT_FAILED
            ENDIF
        ELSE
            lcTexto = loRemoto.TextoIndice()
            IF EMPTY(lcTexto)
                Console.Error("foxpack: cannot read the index: " + loRemoto.cFallo)
                RETURN FP_EXIT_DOWNLOAD
            ENDIF
            loIndice = NEWOBJECT("Indice", "indice.prg")
            IF !loIndice.Leer(lcTexto)
                Console.Error("foxpack: " + loIndice.cFallo)
                RETURN FP_EXIT_DOWNLOAD
            ENDIF
            loEntrada = loIndice.Buscar(lcSpec)
            IF ISNULL(loEntrada)
                Console.Error("foxpack: '" + lcSpec + "' is not in the FoxPack index. " + ;
                    "For a library on GitHub, use github:user/repo")
                RETURN FP_EXIT_NOT_FOUND
            ENDIF
            lcRepo = loEntrada.cRepo
        ENDIF

        *-- 2. Qué versión, y en qué commit está.
        lcTexto = loRemoto.TextoEtiquetas(lcRepo)
        IF EMPTY(lcTexto)
            Console.Error("foxpack: cannot read the tags of " + lcRepo + ": " + loRemoto.cFallo)
            RETURN IIF(loRemoto.lNoExiste, FP_EXIT_NOT_FOUND, FP_EXIT_DOWNLOAD)
        ENDIF
        loEtiquetas = NEWOBJECT("Etiquetas", "indice.prg")
        IF !loEtiquetas.Leer(lcTexto)
            Console.Error("foxpack: " + loEtiquetas.cFallo)
            RETURN FP_EXIT_DOWNLOAD
        ENDIF
        IF EMPTY(lcVersion)
            loEtq = loEtiquetas.Ultima()
        ELSE
            loEtq = loEtiquetas.Elegir(lcVersion)
        ENDIF
        IF ISNULL(loEtq)
            IF loEtiquetas.oLista.Count = 0
                Console.Error("foxpack: " + lcRepo + " has no version tags (like v1.0)")
            ELSE
                Console.Error("foxpack: " + lcRepo + " has no version " + lcVersion + ;
                    ". Versions: " + loEtiquetas.Todas())
            ENDIF
            RETURN FP_EXIT_NOT_FOUND
        ENDIF

        *-- 3. Su foxpack.json en ese commit, y que diga lo mismo que la
        *-- etiqueta: una etiqueta v13.1.1 con un manifiesto 13.1 es justo
        *-- el lío que esto viene a evitar.
        lcTexto = loRemoto.TextoFichero(lcRepo, loEtq.cCommit, "foxpack.json")
        IF EMPTY(lcTexto)
            IF loRemoto.lNoExiste
                Console.Error("foxpack: " + lcRepo + " has no foxpack.json at " + loEtq.cEtiqueta)
                RETURN FP_EXIT_BAD_MANIFEST
            ENDIF
            Console.Error("foxpack: " + loRemoto.cFallo)
            RETURN FP_EXIT_DOWNLOAD
        ENDIF
        loManif = NEWOBJECT("Manifiesto", "manifiesto.prg")
        IF !loManif.Leer(lcTexto)
            Console.Error("foxpack: " + lcRepo + "@" + loEtq.cEtiqueta + ": " + loManif.cFallo)
            RETURN FP_EXIT_BAD_MANIFEST
        ENDIF
        IF !(loEtiquetas.SinV(loManif.cVersion) == loEtq.cVersion)
            Console.Error("foxpack: " + lcRepo + ": the tag says " + loEtq.cVersion + ;
                " and foxpack.json says " + loManif.cVersion)
            RETURN FP_EXIT_BAD_MANIFEST
        ENDIF
        IF !llDeGithub AND !(loManif.cNombre == LOWER(lcSpec))
            Console.Error("foxpack: the index calls it '" + LOWER(lcSpec) + ;
                "' and its foxpack.json calls it '" + loManif.cNombre + "'")
            RETURN FP_EXIT_BAD_MANIFEST
        ENDIF
        lcNombre = loManif.cNombre

        *-- 4. Si ya está: con el mismo commit no hay nada que hacer; con
        *-- otro, se cambia, pero no si alguien ha tocado la copia.
        loActual = loCandado.Buscar(lcNombre)
        IF !ISNULL(loActual)
            IF loActual.cCommit == loEtq.cCommit
                Console.WriteLine(lcNombre + " " + loActual.cVersion + " is already installed")
                RETURN EXIT_OK
            ENDIF
            lcCambios = THIS.CopiasTocadas(lcCarpeta, loActual)
            IF !EMPTY(lcCambios)
                Console.Error("foxpack: lib\" + lcNombre + " has local changes (" + lcCambios + ;
                    "). A library's copy is never edited: fix it in its repository.")
                RETURN FP_EXIT_CHANGED
            ENDIF
        ENDIF

        *-- 5. Bajar, entera o nada, y apuntarla.
        loInst = NEWOBJECT("Instalador", "instalador.prg")
        loLib = loInst.Instalar(lcCarpeta, lcNombre, lcRepo, loEtq.cCommit, loManif.oFicheros, .NULL.)
        IF ISNULL(loLib)
            Console.Error("foxpack: " + loInst.cFallo)
            RETURN EVL(loInst.nCodigo, EXIT_FAILED)
        ENDIF
        loLib.cVersion = loEtq.cVersion
        IF !ISNULL(loActual)
            loCandado.oLibrerias.Remove(LOWER(lcNombre))
        ENDIF
        loCandado.oLibrerias.Add(loLib, LOWER(lcNombre))
        IF !loCandado.Escribir(lcCarpeta + "foxpack.lock")
            Console.Error("foxpack: " + loCandado.cFallo)
            RETURN EXIT_FAILED
        ENDIF

        Console.WriteLine("Installed " + lcNombre + " " + loLib.cVersion + " (" + LEFT(loLib.cCommit, 7) + ;
            ") in lib\" + lcNombre + "\")
        FOR lnI = 1 TO loLib.oFicheros.Count
            loF = loLib.oFicheros.Item(lnI)
            Console.WriteLine("  lib\" + lcNombre + "\" + CHRTRAN(loF.cRuta, "/", "\"))
        ENDFOR
        IF !EMPTY(loManif.cUso)
            Console.WriteLine("Use it with: " + loManif.cUso)
        ENDIF
        RETURN EXIT_OK
    ENDPROC


    *!* Download exactly what foxpack.lock says
    *!* For a fresh clone, or to repair a damaged copy. A library whose copy
    *!* already matches is left alone.
    *!* @tcProject -p =.     Project folder
    PROCEDURE Restore(tcProject AS String)
        LOCAL lcCarpeta, loCandado, loLib, loInst, loNueva, loRutas, loShas, loF
        LOCAL lnI, lnJ, lnRes

        lcCarpeta = THIS.Carpeta(tcProject)
        IF EMPTY(lcCarpeta)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF
        loCandado = THIS.LeerCandado(lcCarpeta)
        IF ISNULL(loCandado)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF
        IF loCandado.oLibrerias.Count = 0
            Console.WriteLine("Nothing to restore: foxpack.lock lists no libraries")
            RETURN EXIT_OK
        ENDIF

        lnRes = EXIT_OK
        loInst = NEWOBJECT("Instalador", "instalador.prg")
        FOR lnI = 1 TO loCandado.oLibrerias.Count
            loLib = loCandado.oLibrerias.Item(lnI)
            IF EMPTY(THIS.CopiasTocadas(lcCarpeta, loLib))
                Console.WriteLine("ok        " + loLib.cNombre + " " + loLib.cVersion)
                LOOP
            ENDIF
            loRutas = CREATEOBJECT("Collection")
            loShas = CREATEOBJECT("Collection")
            FOR lnJ = 1 TO loLib.oFicheros.Count
                loF = loLib.oFicheros.Item(lnJ)
                loRutas.Add(loF.cRuta)
                loShas.Add(loF.cSha256)
            ENDFOR
            loNueva = loInst.Instalar(lcCarpeta, loLib.cNombre, loLib.cRepo, loLib.cCommit, loRutas, loShas)
            IF ISNULL(loNueva)
                Console.Error("foxpack: " + loLib.cNombre + ": " + loInst.cFallo)
                lnRes = EVL(loInst.nCodigo, EXIT_FAILED)
            ELSE
                Console.WriteLine("restored  " + loLib.cNombre + " " + loLib.cVersion)
            ENDIF
        ENDFOR
        RETURN lnRes
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


    *-- .T. si se puede seguir: con --yes, o si la persona dice que sí. Sin
    *-- nadie delante (entrada redirigida) y sin --yes, no: un script que
    *-- instala código ajeno tiene que decirlo con todas las letras.
    PROTECTED FUNCTION Confirmar(tcAviso, tlYes)
        LOCAL lcRespuesta
        IF tlYes
            RETURN .T.
        ENDIF
        IF Console.IsInputRedirected()
            Console.Error("foxpack: " + tcAviso + " Run it again with --yes to install it.")
            RETURN .F.
        ENDIF
        Console.WriteLine(tcAviso)
        lcRespuesta = Console.Prompt("Install it? [y/N] ")
        IF !ISNULL(lcRespuesta) AND (LOWER(ALLTRIM(lcRespuesta)) == "y" OR LOWER(ALLTRIM(lcRespuesta)) == "yes")
            RETURN .T.
        ENDIF
        Console.Error("foxpack: cancelled")
        RETURN .F.
    ENDFUNC


    *-- Los ficheros de una librería cuya copia no es la del candado, en
    *-- texto («changed JsonFox.prg, missing otro.h»); vacío si están todos.
    PROTECTED FUNCTION CopiasTocadas(tcCarpeta, toLib)
        LOCAL loHuella, lnJ, loF, lcRuta, lcSha, lcSalida
        loHuella = NEWOBJECT("Huella", "huella.prg")
        lcSalida = ""
        FOR lnJ = 1 TO toLib.oFicheros.Count
            loF = toLib.oFicheros.Item(lnJ)
            lcRuta = tcCarpeta + "lib\" + toLib.cNombre + "\" + CHRTRAN(loF.cRuta, "/", "\")
            lcSha = loHuella.DeFichero(lcRuta)
            IF !(lcSha == loF.cSha256)
                lcSalida = lcSalida + IIF(EMPTY(lcSalida), "", ", ") + ;
                    IIF(EMPTY(lcSha), "missing ", "changed ") + loF.cRuta
            ENDIF
        ENDFOR
        RETURN lcSalida
    ENDFUNC


    *-- Los comandos de las fases que faltan.
    PROTECTED FUNCTION TodaviaNo(tcComando)
        Console.Error("foxpack: '" + tcComando + "' is not available yet in this build")
        RETURN EXIT_FAILED
    ENDFUNC

ENDDEFINE
