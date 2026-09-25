*==================================================================
* manifiesto.prg -- foxpack.json: cómo se describe una librería
*
* Lo escribe el autor de la librería, en la raíz de su repo:
*
*     {
*       "name": "jsonfox",
*       "version": "13.1.1",
*       "description": "JSON parser and serializer for VFP in a single PRG",
*       "license": "MIT",
*       "files": ["JsonFox.prg"],
*       "usage": "loJson = NEWOBJECT(\"JSONFox\", \"JsonFox.prg\")"
*     }
*
* Son datos y nada más: instalar una librería no ejecuta nada suyo.
* files son rutas dentro del repo; en la v0.1, solo .prg y .h (un .vcx o
* un .scx van en pareja con su memo y quedan para después).
*==================================================================

DEFINE CLASS Manifiesto AS Custom

    cFallo = ""
    cNombre = ""
    cVersion = ""
    cDescripcion = ""
    cLicencia = ""
    cUso = ""
    *-- Las rutas de files, como texto, en su orden.
    oFicheros = .NULL.

    PROCEDURE Init
        THIS.oFicheros = CREATEOBJECT("Collection")
    ENDPROC


    *-- Lee y valida el texto de un foxpack.json. .F. con el motivo en
    *-- cFallo si no vale.
    FUNCTION Leer(tcTexto)
        LOCAL loJson, loRaiz, loLista, lnI, lcRuta, llBien, loErr

        THIS.cFallo = ""
        THIS.oFicheros = CREATEOBJECT("Collection")
        llBien = .F.
        TRY
            loJson = NEWOBJECT("JSONFox", "JsonFox.prg")
            loRaiz = loJson.Parse(tcTexto)
            IF loJson.lError
                THIS.cFallo = "foxpack.json is not valid JSON: " + loJson.cLastError
            ELSE
                llBien = .T.
            ENDIF
        CATCH TO loErr
            THIS.cFallo = "foxpack.json is not valid JSON: " + loErr.Message
        ENDTRY
        IF !llBien
            RETURN .F.
        ENDIF
        IF VARTYPE(loRaiz) <> "O"
            THIS.cFallo = "foxpack.json is not an object"
            RETURN .F.
        ENDIF

        THIS.cNombre = LOWER(THIS.Texto(loRaiz, "name"))
        THIS.cVersion = THIS.Texto(loRaiz, "version")
        THIS.cDescripcion = THIS.Texto(loRaiz, "description")
        THIS.cLicencia = THIS.Texto(loRaiz, "license")
        THIS.cUso = THIS.Texto(loRaiz, "usage")

        DO CASE
        CASE EMPTY(THIS.cNombre)
            THIS.cFallo = "foxpack.json has no name"
        CASE LEN(CHRTRAN(THIS.cNombre, "abcdefghijklmnopqrstuvwxyz0123456789-_.", "")) > 0
            THIS.cFallo = "foxpack.json: the name may only have letters, digits, - _ and ."
        CASE EMPTY(THIS.cVersion)
            THIS.cFallo = "foxpack.json has no version"
        CASE TYPE("loRaiz.files") <> "O"
            THIS.cFallo = "foxpack.json has no files list"
        ENDCASE
        IF !EMPTY(THIS.cFallo)
            RETURN .F.
        ENDIF

        loLista = loRaiz.files
        FOR lnI = 1 TO loLista.Count
            lcRuta = loLista.Item(lnI)
            IF VARTYPE(lcRuta) <> "C" OR !THIS.RutaAdmitida(lcRuta)
                THIS.cFallo = "foxpack.json: file " + TRANSFORM(lnI) + " is not a .prg or .h " + ;
                    "inside the repository: " + TRANSFORM(lcRuta)
                RETURN .F.
            ENDIF
            THIS.oFicheros.Add(CHRTRAN(ALLTRIM(lcRuta), "\", "/"))
        ENDFOR
        IF THIS.oFicheros.Count = 0
            THIS.cFallo = "foxpack.json has an empty files list"
            RETURN .F.
        ENDIF
        RETURN .T.
    ENDFUNC


    *-- Relativa, sin «..», y .prg o .h.
    PROTECTED FUNCTION RutaAdmitida(tcRuta)
        LOCAL lcRuta
        lcRuta = CHRTRAN(ALLTRIM(tcRuta), "\", "/")
        IF EMPTY(lcRuta) OR LEFT(lcRuta, 1) == "/" OR ":" $ lcRuta OR ".." $ lcRuta
            RETURN .F.
        ENDIF
        *-- == y no INLIST, que respeta SET EXACT (regla 17).
        RETURN LOWER(JUSTEXT(lcRuta)) == "prg" OR LOWER(JUSTEXT(lcRuta)) == "h"
    ENDFUNC


    PROTECTED FUNCTION Texto(toObj, tcClave)
        LOCAL lcValor
        lcValor = ""
        IF TYPE("toObj." + tcClave) == "C"
            lcValor = ALLTRIM(EVALUATE("toObj." + tcClave))
        ENDIF
        RETURN lcValor
    ENDFUNC

ENDDEFINE
