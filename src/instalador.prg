*==================================================================
* instalador.prg -- deja una librería en lib\<librería>\, entera o nada
*
* Los ficheros se bajan primero a una carpeta temporal dentro de lib\
* (lib\.foxpack-<algo>\), se hashean allí, y solo cuando han llegado
* TODOS se cambia la carpeta de la librería por la nueva. Si falla el
* tercero de cinco, lib\ se queda como estaba: ni a medias ni vacía.
*
* La temporal va dentro de lib\ para que el cambio sea un MoveFolder en
* el mismo disco, que es un renombrado y no una copia.
*
* También escribe lib\.gitattributes con «* -text» si no está: con
* core.autocrlf=true, git cambiaría los finales de línea de las copias
* al hacer checkout, su SHA-256 dejaría de ser el de foxpack.lock y
* verify las daría todas por tocadas.
*==================================================================

DEFINE CLASS Instalador AS Custom

    cFallo = ""
    *-- El exit code que corresponde al fallo: 10 si algo no existe en el
    *-- repo, 11 si no se pudo bajar o no es lo que dice el candado.
    nCodigo = 0
    oRemoto = .NULL.
    oHuella = .NULL.

    PROCEDURE Init
        THIS.oRemoto = NEWOBJECT("Remoto", "remoto.prg")
        THIS.oHuella = NEWOBJECT("Huella", "huella.prg")
    ENDPROC


    *-- Instala tcNombre bajando toRutas (Collection de rutas del repo) de
    *-- tcRepo en tcCommit. Si toShas trae los SHA-256 esperados (mismo
    *-- orden), un fichero que no coincida hace fallar la instalación: es
    *-- lo que usa restore. Devuelve una LibreriaCandado con los hashes de
    *-- lo instalado, o .NULL. con cFallo y nCodigo.
    FUNCTION Instalar(tcCarpeta, tcNombre, tcRepo, tcCommit, toRutas, toShas)
        LOCAL lcLib, lcTemp, lcDestino, lcRuta, lcSha, lnI, loLib, llBien, loErr, loFso

        THIS.cFallo = ""
        THIS.nCodigo = 0
        lcLib = ADDBS(tcCarpeta) + "lib\"
        lcTemp = lcLib + ".foxpack-" + SYS(2015) + "\"
        loLib = NEWOBJECT("LibreriaCandado", "candado.prg")
        loLib.cNombre = tcNombre
        loLib.cRepo = tcRepo
        loLib.cCommit = tcCommit

        IF !THIS.CrearCarpeta(lcTemp)
            RETURN .NULL.
        ENDIF

        llBien = .T.
        FOR lnI = 1 TO toRutas.Count
            lcRuta = toRutas.Item(lnI)
            lcDestino = lcTemp + CHRTRAN(lcRuta, "/", "\")
            IF !THIS.CrearCarpeta(ADDBS(JUSTPATH(lcDestino)))
                llBien = .F.
                EXIT
            ENDIF
            IF !THIS.oRemoto.BajarFichero(tcRepo, tcCommit, lcRuta, lcDestino)
                THIS.cFallo = THIS.oRemoto.cFallo
                THIS.nCodigo = 11
                llBien = .F.
                EXIT
            ENDIF
            lcSha = THIS.oHuella.DeFichero(lcDestino)
            IF EMPTY(lcSha)
                THIS.cFallo = THIS.oHuella.cFallo
                THIS.nCodigo = 11
                llBien = .F.
                EXIT
            ENDIF
            IF VARTYPE(toShas) == "O" AND !(lcSha == LOWER(toShas.Item(lnI)))
                THIS.cFallo = lcRuta + " from " + tcRepo + "@" + LEFT(tcCommit, 7) + ;
                    " is not the file foxpack.lock recorded (SHA-256 differs)"
                THIS.nCodigo = 11
                llBien = .F.
                EXIT
            ENDIF
            loLib.AnadirFichero(lcRuta, lcSha)
        ENDFOR

        loFso = CREATEOBJECT("Scripting.FileSystemObject")
        IF llBien
            TRY
                IF DIRECTORY(lcLib + tcNombre)
                    loFso.DeleteFolder(lcLib + tcNombre, .T.)
                ENDIF
                loFso.MoveFolder(LEFT(lcTemp, LEN(lcTemp) - 1), lcLib + tcNombre)
            CATCH TO loErr
                THIS.cFallo = "cannot replace " + lcLib + tcNombre + ": " + loErr.Message
                THIS.nCodigo = 1
                llBien = .F.
            ENDTRY
        ENDIF
        IF !llBien
            TRY
                IF DIRECTORY(lcTemp)
                    loFso.DeleteFolder(LEFT(lcTemp, LEN(lcTemp) - 1), .T.)
                ENDIF
            CATCH
            ENDTRY
            RETURN .NULL.
        ENDIF

        THIS.EscribirGitattributes(lcLib)
        RETURN loLib
    ENDFUNC


    *-- Borra lib\<librería>\ entera. .T. si ya no está.
    FUNCTION Quitar(tcCarpeta, tcNombre)
        LOCAL lcDir, loFso, loErr
        THIS.cFallo = ""
        lcDir = ADDBS(tcCarpeta) + "lib\" + tcNombre
        IF !DIRECTORY(lcDir)
            RETURN .T.
        ENDIF
        TRY
            loFso = CREATEOBJECT("Scripting.FileSystemObject")
            loFso.DeleteFolder(lcDir, .T.)
        CATCH TO loErr
            THIS.cFallo = "cannot delete " + lcDir + ": " + loErr.Message
        ENDTRY
        RETURN !DIRECTORY(lcDir)
    ENDFUNC


    PROTECTED FUNCTION CrearCarpeta(tcDir)
        LOCAL loErr, llBien
        llBien = .T.
        IF !DIRECTORY(tcDir)
            TRY
                MD (tcDir)
            CATCH TO loErr
                THIS.cFallo = "cannot create " + tcDir + ": " + loErr.Message
                THIS.nCodigo = 1
                llBien = .F.
            ENDTRY
        ENDIF
        RETURN llBien
    ENDFUNC


    PROTECTED PROCEDURE EscribirGitattributes(tcLib)
        LOCAL ARRAY laEsta[1]
        IF ADIR(laEsta, tcLib + ".gitattributes", "H") > 0
            RETURN
        ENDIF
        TRY
            STRTOFILE("# Written by FoxPack: library copies keep their exact bytes, so their" + CHR(13) + CHR(10) + ;
                      "# SHA-256 stays the one in foxpack.lock." + CHR(13) + CHR(10) + ;
                      "* -text" + CHR(13) + CHR(10), tcLib + ".gitattributes")
        CATCH
        ENDTRY
    ENDPROC

ENDDEFINE
