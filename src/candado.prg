*==================================================================
* candado.prg -- foxpack.lock: qué hay instalado, y exactamente qué
*
*     {
*       "lockVersion": 1,
*       "libraries": [
*         {
*           "name": "jsonfox",
*           "repo": "Irwin1985/JSONFox",
*           "version": "13.1",
*           "commit": "23c31883ec9067efc5ef44d819606d79826f5221",
*           "files": [
*             { "path": "JsonFox.prg", "sha256": "2fdf58c5..." }
*           ]
*         }
*       ]
*     }
*
* Listas y no objetos con claves ("libraries": { "jsonfox": ... }), que
* era el borrador de PLAN-FOXPACK.md: JSONFox convierte cada clave en
* una propiedad de VFP, y una propiedad pierde las mayúsculas y no puede
* llevar un punto. «JsonFox.prg» como clave no llega entero.
*
* Se lee con JSONFox y se escribe a mano: así el orden de las claves y
* sus mayúsculas son las de arriba, y el fichero sale igual cada vez
* (un diff de git enseña solo lo que cambió).
*==================================================================

DEFINE CLASS Candado AS Custom

    cFallo = ""
    *-- .F. si foxpack.lock no existía al leer: no hay nada instalado.
    lExiste = .F.
    *-- Las librerías, LibreriaCandado con su nombre en minúsculas de clave.
    oLibrerias = .NULL.

    PROCEDURE Init
        THIS.oLibrerias = CREATEOBJECT("Collection")
    ENDPROC


    *-- Lee foxpack.lock. .T. si se pudo leer o si no existe (entonces
    *-- lExiste = .F. y no hay librerías); .F. si existe y está roto.
    FUNCTION Leer(tcRuta)
        LOCAL lcTexto, loJson, loRaiz, loLista, loItem, loLib, loFichs, loF
        LOCAL lnI, lnJ, llBien, loErr
        LOCAL ARRAY laEsta[1]

        THIS.cFallo = ""
        THIS.oLibrerias = CREATEOBJECT("Collection")
        THIS.lExiste = (ADIR(laEsta, tcRuta) > 0)
        IF !THIS.lExiste
            RETURN .T.
        ENDIF

        llBien = .F.
        TRY
            lcTexto = FILETOSTR(tcRuta)
            loJson = NEWOBJECT("JSONFox", "JsonFox.prg")
            loRaiz = loJson.Parse(lcTexto)
            IF loJson.lError
                THIS.cFallo = "foxpack.lock is not valid JSON: " + loJson.cLastError
            ELSE
                llBien = .T.
            ENDIF
        CATCH TO loErr
            THIS.cFallo = "cannot read foxpack.lock: " + loErr.Message
        ENDTRY
        IF !llBien
            RETURN .F.
        ENDIF

        IF VARTYPE(loRaiz) <> "O" OR TYPE("loRaiz.libraries") <> "O"
            THIS.cFallo = "foxpack.lock has no libraries list"
            RETURN .F.
        ENDIF

        loLista = loRaiz.libraries
        FOR lnI = 1 TO loLista.Count
            loItem = loLista.Item(lnI)
            loLib = CREATEOBJECT("LibreriaCandado")
            loLib.cNombre = THIS.Texto(loItem, "name")
            loLib.cRepo = THIS.Texto(loItem, "repo")
            loLib.cVersion = THIS.Texto(loItem, "version")
            loLib.cCommit = THIS.Texto(loItem, "commit")
            IF EMPTY(loLib.cNombre)
                THIS.cFallo = "foxpack.lock: library " + TRANSFORM(lnI) + " has no name"
                RETURN .F.
            ENDIF
            IF TYPE("loItem.files") = "O"
                loFichs = loItem.files
                FOR lnJ = 1 TO loFichs.Count
                    loF = loFichs.Item(lnJ)
                    loLib.AnadirFichero(THIS.Texto(loF, "path"), THIS.Texto(loF, "sha256"))
                ENDFOR
            ENDIF
            IF !ISNULL(THIS.Buscar(loLib.cNombre))
                THIS.cFallo = "foxpack.lock: library '" + loLib.cNombre + "' appears twice"
                RETURN .F.
            ENDIF
            THIS.oLibrerias.Add(loLib, LOWER(loLib.cNombre))
        ENDFOR
        RETURN .T.
    ENDFUNC


    *-- Escribe foxpack.lock entero, con las librerías por nombre.
    FUNCTION Escribir(tcRuta)
        LOCAL lcJson, lnI, lnJ, loLib, loF, llBien, loErr, lcSafety
        LOCAL ARRAY laNombres[1]

        THIS.cFallo = ""
        lcJson = '{' + CHR(13) + CHR(10) + ;
                 '  "lockVersion": 1,' + CHR(13) + CHR(10) + ;
                 '  "libraries": ['

        FOR lnI = 1 TO THIS.oLibrerias.Count
            loLib = THIS.oLibrerias.Item(lnI)
            lcJson = lcJson + IIF(lnI > 1, ",", "") + CHR(13) + CHR(10) + ;
                '    {' + CHR(13) + CHR(10) + ;
                '      "name": ' + THIS.Cadena(loLib.cNombre) + ',' + CHR(13) + CHR(10) + ;
                '      "repo": ' + THIS.Cadena(loLib.cRepo) + ',' + CHR(13) + CHR(10) + ;
                '      "version": ' + THIS.Cadena(loLib.cVersion) + ',' + CHR(13) + CHR(10) + ;
                '      "commit": ' + THIS.Cadena(loLib.cCommit) + ',' + CHR(13) + CHR(10) + ;
                '      "files": ['
            FOR lnJ = 1 TO loLib.oFicheros.Count
                loF = loLib.oFicheros.Item(lnJ)
                lcJson = lcJson + IIF(lnJ > 1, ",", "") + CHR(13) + CHR(10) + ;
                    '        { "path": ' + THIS.Cadena(loF.cRuta) + ;
                    ', "sha256": ' + THIS.Cadena(loF.cSha256) + ' }'
            ENDFOR
            lcJson = lcJson + IIF(loLib.oFicheros.Count > 0, CHR(13) + CHR(10) + '      ', '') + ;
                ']' + CHR(13) + CHR(10) + '    }'
        ENDFOR

        lcJson = lcJson + IIF(THIS.oLibrerias.Count > 0, CHR(13) + CHR(10) + '  ', '') + ;
                 ']' + CHR(13) + CHR(10) + '}' + CHR(13) + CHR(10)

        *-- Regla 63: STRTOFILE sobre un fichero que existe pregunta con
        *-- SAFETY ON. En una DLL no hay a quién preguntar.
        lcSafety = SET("SAFETY")
        SET SAFETY OFF
        llBien = .F.
        TRY
            STRTOFILE(lcJson, tcRuta)
            llBien = .T.
        CATCH TO loErr
            THIS.cFallo = "cannot write foxpack.lock: " + loErr.Message
        ENDTRY
        IF lcSafety == "ON"
            SET SAFETY ON
        ENDIF
        RETURN llBien
    ENDFUNC


    *-- La librería con ese nombre, o .NULL.
    FUNCTION Buscar(tcNombre)
        LOCAL loLib, loUna, lnI
        loLib = .NULL.
        FOR lnI = 1 TO THIS.oLibrerias.Count
            loUna = THIS.oLibrerias.Item(lnI)
            IF LOWER(loUna.cNombre) == LOWER(ALLTRIM(tcNombre))
                loLib = loUna
                EXIT
            ENDIF
        ENDFOR
        RETURN loLib
    ENDFUNC


    *-- Un texto del objeto que dio JSONFox; vacío si no está o no es texto.
    PROTECTED FUNCTION Texto(toObj, tcClave)
        LOCAL lcValor
        lcValor = ""
        IF TYPE("toObj." + tcClave) == "C"
            lcValor = EVALUATE("toObj." + tcClave)
        ENDIF
        RETURN lcValor
    ENDFUNC


    *-- Una cadena JSON entre comillas, con lo que hay que escapar escapado.
    PROTECTED FUNCTION Cadena(tcTexto)
        LOCAL lcSalida, lnI, lcC, lnA
        lcSalida = ""
        FOR lnI = 1 TO LEN(tcTexto)
            lcC = SUBSTR(tcTexto, lnI, 1)
            lnA = ASC(lcC)
            DO CASE
            CASE lcC == '"'
                lcSalida = lcSalida + '\"'
            CASE lcC == "\"
                lcSalida = lcSalida + "\\"
            CASE lnA < 32
                lcSalida = lcSalida + "\u" + RIGHT("000" + LOWER(TRANSFORM(lnA, "@0")), 4)
            OTHERWISE
                lcSalida = lcSalida + lcC
            ENDCASE
        ENDFOR
        RETURN '"' + lcSalida + '"'
    ENDFUNC

ENDDEFINE


*-- Una librería del candado.
DEFINE CLASS LibreriaCandado AS Custom

    cNombre = ""
    cRepo = ""
    cVersion = ""
    cCommit = ""
    *-- FicheroCandado, en el orden en que se instalaron.
    oFicheros = .NULL.

    PROCEDURE Init
        THIS.oFicheros = CREATEOBJECT("Collection")
    ENDPROC

    PROCEDURE AnadirFichero(tcRuta, tcSha256)
        LOCAL loF
        loF = CREATEOBJECT("FicheroCandado")
        loF.cRuta = tcRuta
        loF.cSha256 = LOWER(tcSha256)
        THIS.oFicheros.Add(loF)
    ENDPROC

ENDDEFINE


*-- Un fichero de una librería: su ruta dentro de lib\<librería>\ y su
*-- SHA-256 en hexadecimal y minúsculas.
DEFINE CLASS FicheroCandado AS Custom
    cRuta = ""
    cSha256 = ""
ENDDEFINE
