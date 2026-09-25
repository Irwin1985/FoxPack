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

    *-- Lo que deja InstalarEtiqueta para quien la llama (add y update).
    PROTECTED oInstalada, cUsoInstalada, cNombreInstalado, nSalida
    oInstalada = .NULL.
    cUsoInstalada = ""
    cNombreInstalado = ""
    nSalida = 0

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
        LOCAL lcCarpeta, loCandado, lcSpec, lcVersion, lcRepo, lcNombre, llDeGithub, lnPos
        LOCAL loRemoto, loIndice, loEntrada, loEtq, lcTexto, lnSalida, loLib, loF, lnI

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

        *-- 1. De qué repo sale. Del índice, el nombre que tiene que traer
        *-- su foxpack.json es el del índice; de github:, el que traiga.
        IF llDeGithub
            lcRepo = ALLTRIM(SUBSTR(lcSpec, 8))
            lcNombre = ""
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
            lcNombre = loEntrada.cNombre
        ENDIF

        *-- 2. Qué versión, y en qué commit está.
        loEtq = THIS.BuscarEtiqueta(loRemoto, lcRepo, lcVersion)
        IF ISNULL(loEtq)
            RETURN THIS.nSalida
        ENDIF

        *-- 3. Bajarla y apuntarla (sin --force: add no pisa una copia tocada).
        lnSalida = THIS.InstalarEtiqueta(lcCarpeta, loCandado, loRemoto, lcRepo, loEtq, lcNombre, .F.)
        IF lnSalida <> EXIT_OK
            RETURN lnSalida
        ENDIF
        loLib = THIS.oInstalada
        IF ISNULL(loLib)
            Console.WriteLine(THIS.cNombreInstalado + " " + loEtq.cVersion + " is already installed")
            RETURN EXIT_OK
        ENDIF

        Console.WriteLine("Installed " + loLib.cNombre + " " + loLib.cVersion + " (" + ;
            LEFT(loLib.cCommit, 7) + ") in lib\" + loLib.cNombre + "\")
        FOR lnI = 1 TO loLib.oFicheros.Count
            loF = loLib.oFicheros.Item(lnI)
            Console.WriteLine("  lib\" + loLib.cNombre + "\" + CHRTRAN(loF.cRuta, "/", "\"))
        ENDFOR
        IF !EMPTY(THIS.cUsoInstalada)
            Console.WriteLine("Use it with: " + THIS.cUsoInstalada)
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
    *!* A library whose copy was changed by hand is not updated unless you
    *!* say --force: the change would be lost.
    *!* @tcLibrary <> =      The library; without it, all of them
    *!* @tcProject -p =.     Project folder
    *!* @tlForce   -f        Overwrite a copy that someone has changed
    *!* @example foxpack update
    *!* @example foxpack update jsonfox
    PROCEDURE Update(tcLibrary AS String, tcProject AS String, tlForce AS Logical)
        LOCAL lcCarpeta, loCandado, loRemoto, loLib, loEtq, loTodas, lcAntes, lnI, lnSalida, lnRes

        lcCarpeta = THIS.Carpeta(tcProject)
        IF EMPTY(lcCarpeta)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF
        loCandado = THIS.LeerCandado(lcCarpeta)
        IF ISNULL(loCandado)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF

        *-- Cuáles: la que se nombra, o todas. Sin nombre llega .F. (el
        *-- parámetro es opcional y no tiene valor por defecto).
        loTodas = CREATEOBJECT("Collection")
        IF VARTYPE(tcLibrary) == "C" AND !EMPTY(tcLibrary)
            loLib = loCandado.Buscar(tcLibrary)
            IF ISNULL(loLib)
                Console.Error("foxpack: '" + ALLTRIM(tcLibrary) + "' is not installed. " + ;
                    "To install it: foxpack add " + ALLTRIM(tcLibrary))
                RETURN FP_EXIT_NOT_FOUND
            ENDIF
            loTodas.Add(loLib)
        ELSE
            FOR lnI = 1 TO loCandado.oLibrerias.Count
                loTodas.Add(loCandado.oLibrerias.Item(lnI))
            ENDFOR
        ENDIF
        IF loTodas.Count = 0
            Console.WriteLine("Nothing to update: foxpack.lock lists no libraries")
            RETURN EXIT_OK
        ENDIF

        lnRes = EXIT_OK
        loRemoto = NEWOBJECT("Remoto", "remoto.prg")
        FOR lnI = 1 TO loTodas.Count
            loLib = loTodas.Item(lnI)
            lcAntes = loLib.cVersion
            loEtq = THIS.BuscarEtiqueta(loRemoto, loLib.cRepo, "")
            IF ISNULL(loEtq)
                lnRes = THIS.nSalida
                LOOP
            ENDIF
            IF loEtq.cCommit == loLib.cCommit
                Console.WriteLine("up to date  " + loLib.cNombre + " " + loLib.cVersion)
                LOOP
            ENDIF
            lnSalida = THIS.InstalarEtiqueta(lcCarpeta, loCandado, loRemoto, loLib.cRepo, loEtq, ;
                loLib.cNombre, tlForce)
            IF lnSalida = EXIT_OK
                Console.WriteLine("updated     " + loLib.cNombre + " " + lcAntes + " -> " + loEtq.cVersion)
            ELSE
                lnRes = lnSalida
            ENDIF
        ENDFOR
        RETURN lnRes
    ENDPROC


    *!* Remove a library from lib\ and from foxpack.lock
    *!* Its files are deleted, local changes included. If the VFP project in
    *!* the folder is closed, they are taken out of it too.
    *!* @tcLibrary <>        The library
    *!* @tcProject -p =.     Project folder
    PROCEDURE Remove(tcLibrary AS String, tcProject AS String)
        LOCAL lcCarpeta, loCandado, loLib, loInst, lcNombre, loPjx, lnQuitadas

        lcCarpeta = THIS.Carpeta(tcProject)
        IF EMPTY(lcCarpeta)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF
        loCandado = THIS.LeerCandado(lcCarpeta)
        IF ISNULL(loCandado)
            RETURN FP_EXIT_NO_PROJECT
        ENDIF
        loLib = loCandado.Buscar(tcLibrary)
        IF ISNULL(loLib)
            Console.Error("foxpack: '" + ALLTRIM(tcLibrary) + "' is not installed")
            RETURN FP_EXIT_NOT_FOUND
        ENDIF
        lcNombre = loLib.cNombre

        loInst = NEWOBJECT("Instalador", "instalador.prg")
        IF !loInst.Quitar(lcCarpeta, lcNombre)
            Console.Error("foxpack: " + loInst.cFallo)
            RETURN EXIT_FAILED
        ENDIF
        loCandado.oLibrerias.Remove(LOWER(lcNombre))
        IF !loCandado.Escribir(lcCarpeta + "foxpack.lock")
            Console.Error("foxpack: " + loCandado.cFallo)
            RETURN EXIT_FAILED
        ENDIF
        Console.WriteLine("Removed " + lcNombre + " " + loLib.cVersion + " and lib\" + lcNombre + "\")

        *-- Y del proyecto VFP, si está cerrado: si no, al abrirlo VFP
        *-- preguntaría por el fichero que falta (proyectovfp.prg).
        loPjx = NEWOBJECT("ProyectoVfp", "proyectovfp.prg")
        lnQuitadas = loPjx.Quitar(lcCarpeta, lcNombre)
        IF lnQuitadas > 0
            Console.WriteLine("Taken out of the project: " + TRANSFORM(lnQuitadas) + " file(s)")
        ENDIF
        IF !EMPTY(loPjx.cOcupados)
            Console.WriteLine("The project is open in VFP (" + CHRTRAN(ALLTRIM(loPjx.cOcupados, 0, CHR(13)), CHR(13), ",") + ;
                "): FoxForge takes the library out of it at the next build (Ctrl+F7).")
        ENDIF
        RETURN EXIT_OK
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


    *-- La etiqueta de tcVersion en tcRepo, o la última si viene vacía.
    *-- .NULL. si no hay: el error ya está escrito y el exit code queda en
    *-- THIS.nSalida.
    PROTECTED FUNCTION BuscarEtiqueta(toRemoto, tcRepo, tcVersion)
        LOCAL lcTexto, loEtiquetas, loEtq

        THIS.nSalida = EXIT_OK
        lcTexto = toRemoto.TextoEtiquetas(tcRepo)
        IF EMPTY(lcTexto)
            Console.Error("foxpack: cannot read the tags of " + tcRepo + ": " + toRemoto.cFallo)
            THIS.nSalida = IIF(toRemoto.lNoExiste, FP_EXIT_NOT_FOUND, FP_EXIT_DOWNLOAD)
            RETURN .NULL.
        ENDIF
        loEtiquetas = NEWOBJECT("Etiquetas", "indice.prg")
        IF !loEtiquetas.Leer(lcTexto)
            Console.Error("foxpack: " + loEtiquetas.cFallo)
            THIS.nSalida = FP_EXIT_DOWNLOAD
            RETURN .NULL.
        ENDIF
        IF EMPTY(tcVersion)
            loEtq = loEtiquetas.Ultima()
        ELSE
            loEtq = loEtiquetas.Elegir(tcVersion)
        ENDIF
        IF ISNULL(loEtq)
            IF loEtiquetas.oLista.Count = 0
                Console.Error("foxpack: " + tcRepo + " has no version tags (like v1.0)")
            ELSE
                Console.Error("foxpack: " + tcRepo + " has no version " + tcVersion + ;
                    ". Versions: " + loEtiquetas.Todas())
            ENDIF
            THIS.nSalida = FP_EXIT_NOT_FOUND
        ENDIF
        RETURN loEtq
    ENDFUNC


    *-- Instala la etiqueta toEtq de tcRepo en el proyecto y la apunta en el
    *-- candado. Lo comparten add y update.
    *--
    *-- tcNombre, si viene, es el nombre que tiene que traer su foxpack.json
    *-- (el del índice, o el del candado en un update). tlForce pisa una
    *-- copia tocada a mano.
    *--
    *-- Devuelve el exit code, con el error ya escrito. Si instaló, la
    *-- librería queda en THIS.oInstalada y su línea de uso en
    *-- THIS.cUsoInstalada; si ya estaba ese mismo commit, THIS.oInstalada
    *-- es .NULL. y THIS.cNombreInstalado dice cuál.
    PROTECTED FUNCTION InstalarEtiqueta(tcCarpeta, toCandado, toRemoto, tcRepo, toEtq, tcNombre, tlForce)
        LOCAL lcTexto, loManif, lcVersion, lcNombre, loActual, lcCambios, loInst, loLib

        THIS.oInstalada = .NULL.
        THIS.cUsoInstalada = ""
        THIS.cNombreInstalado = ""

        *-- Su foxpack.json en ese commit, y que diga lo mismo que la
        *-- etiqueta: una etiqueta v13.1.1 con un manifiesto 13.1 es justo
        *-- el lío que esto viene a evitar.
        lcTexto = toRemoto.TextoFichero(tcRepo, toEtq.cCommit, "foxpack.json")
        IF EMPTY(lcTexto)
            IF toRemoto.lNoExiste
                Console.Error("foxpack: " + tcRepo + " has no foxpack.json at " + toEtq.cEtiqueta)
                RETURN FP_EXIT_BAD_MANIFEST
            ENDIF
            Console.Error("foxpack: " + toRemoto.cFallo)
            RETURN FP_EXIT_DOWNLOAD
        ENDIF
        loManif = NEWOBJECT("Manifiesto", "manifiesto.prg")
        IF !loManif.Leer(lcTexto)
            Console.Error("foxpack: " + tcRepo + "@" + toEtq.cEtiqueta + ": " + loManif.cFallo)
            RETURN FP_EXIT_BAD_MANIFEST
        ENDIF
        lcVersion = loManif.cVersion
        IF UPPER(LEFT(lcVersion, 1)) == "V"
            lcVersion = SUBSTR(lcVersion, 2)
        ENDIF
        IF !(lcVersion == toEtq.cVersion)
            Console.Error("foxpack: " + tcRepo + ": the tag says " + toEtq.cVersion + ;
                " and foxpack.json says " + loManif.cVersion)
            RETURN FP_EXIT_BAD_MANIFEST
        ENDIF
        IF !EMPTY(tcNombre) AND !(loManif.cNombre == LOWER(tcNombre))
            Console.Error("foxpack: " + tcRepo + " should be '" + LOWER(tcNombre) + ;
                "' and its foxpack.json calls it '" + loManif.cNombre + "'")
            RETURN FP_EXIT_BAD_MANIFEST
        ENDIF
        lcNombre = loManif.cNombre
        THIS.cNombreInstalado = lcNombre

        *-- Si ya está: con el mismo commit no hay nada que hacer; con otro,
        *-- se cambia, pero no si alguien ha tocado la copia (salvo tlForce).
        loActual = toCandado.Buscar(lcNombre)
        IF !ISNULL(loActual)
            IF loActual.cCommit == toEtq.cCommit
                RETURN EXIT_OK
            ENDIF
            lcCambios = THIS.CopiasTocadas(tcCarpeta, loActual)
            IF !EMPTY(lcCambios) AND !tlForce
                Console.Error("foxpack: lib\" + lcNombre + " has local changes (" + lcCambios + ;
                    "). A library's copy is never edited: fix it in its repository, " + ;
                    "or use --force to overwrite it.")
                RETURN FP_EXIT_CHANGED
            ENDIF
        ENDIF

        *-- Bajar, entera o nada, y apuntarla.
        loInst = NEWOBJECT("Instalador", "instalador.prg")
        loLib = loInst.Instalar(tcCarpeta, lcNombre, tcRepo, toEtq.cCommit, loManif.oFicheros, .NULL.)
        IF ISNULL(loLib)
            Console.Error("foxpack: " + loInst.cFallo)
            RETURN EVL(loInst.nCodigo, EXIT_FAILED)
        ENDIF
        loLib.cVersion = toEtq.cVersion
        IF !ISNULL(loActual)
            toCandado.oLibrerias.Remove(LOWER(lcNombre))
        ENDIF
        toCandado.oLibrerias.Add(loLib, LOWER(lcNombre))
        IF !toCandado.Escribir(tcCarpeta + "foxpack.lock")
            Console.Error("foxpack: " + toCandado.cFallo)
            RETURN EXIT_FAILED
        ENDIF
        THIS.oInstalada = loLib
        THIS.cUsoInstalada = loManif.cUso
        RETURN EXIT_OK
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


ENDDEFINE
