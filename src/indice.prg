*==================================================================
* indice.prg -- de un nombre a un repo, y de una versión a un commit
*
* Indice lee index.json (repo público Irwin1985/foxpack-index):
*
*     {
*       "indexVersion": 1,
*       "libraries": [
*         { "name": "jsonfox", "repo": "Irwin1985/JSONFox",
*           "description": "JSON for VFP" }
*       ]
*     }
*
* En lista y no con el nombre de clave, por lo mismo que foxpack.lock:
* JSONFox convierte cada clave en una propiedad de VFP.
*
* Las versiones no están en el índice: salen de las etiquetas del repo de
* cada librería (Etiquetas). Publicar una versión es poner una etiqueta.
*==================================================================

DEFINE CLASS Indice AS Custom

    cFallo = ""
    *-- Las entradas, EntradaIndice con el nombre en minúsculas de clave.
    oEntradas = .NULL.

    PROCEDURE Init
        THIS.oEntradas = CREATEOBJECT("Collection")
    ENDPROC


    FUNCTION Leer(tcTexto)
        LOCAL loJson, loRaiz, loLista, loItem, loEntrada, lnI, llBien, loErr

        THIS.cFallo = ""
        THIS.oEntradas = CREATEOBJECT("Collection")
        llBien = .F.
        TRY
            loJson = NEWOBJECT("JSONFox", "JsonFox.prg")
            loRaiz = loJson.Parse(tcTexto)
            llBien = !loJson.lError
            IF !llBien
                THIS.cFallo = "the index is not valid JSON: " + loJson.cLastError
            ENDIF
        CATCH TO loErr
            THIS.cFallo = "the index is not valid JSON: " + loErr.Message
        ENDTRY
        IF !llBien
            RETURN .F.
        ENDIF
        IF VARTYPE(loRaiz) <> "O" OR TYPE("loRaiz.libraries") <> "O"
            THIS.cFallo = "the index has no libraries list"
            RETURN .F.
        ENDIF

        loLista = loRaiz.libraries
        FOR lnI = 1 TO loLista.Count
            loItem = loLista.Item(lnI)
            loEntrada = CREATEOBJECT("EntradaIndice")
            IF TYPE("loItem.name") == "C" AND TYPE("loItem.repo") == "C"
                loEntrada.cNombre = LOWER(ALLTRIM(loItem.name))
                loEntrada.cRepo = ALLTRIM(loItem.repo)
                IF TYPE("loItem.description") == "C"
                    loEntrada.cDescripcion = loItem.description
                ENDIF
                IF !EMPTY(loEntrada.cNombre) AND ISNULL(THIS.Buscar(loEntrada.cNombre))
                    THIS.oEntradas.Add(loEntrada, loEntrada.cNombre)
                ENDIF
            ENDIF
        ENDFOR
        RETURN .T.
    ENDFUNC


    *-- La entrada con ese nombre, o .NULL.
    FUNCTION Buscar(tcNombre)
        LOCAL loEntrada, loUna, lnI
        loEntrada = .NULL.
        FOR lnI = 1 TO THIS.oEntradas.Count
            loUna = THIS.oEntradas.Item(lnI)
            IF loUna.cNombre == LOWER(ALLTRIM(tcNombre))
                loEntrada = loUna
                EXIT
            ENDIF
        ENDFOR
        RETURN loEntrada
    ENDFUNC

ENDDEFINE


DEFINE CLASS EntradaIndice AS Custom
    cNombre = ""
    cRepo = ""
    cDescripcion = ""
ENDDEFINE


*==================================================================
* Etiquetas -- las versiones de un repo
*
* Del JSON de la API de GitHub (GET /repos/{repo}/tags): una lista con
* name y commit.sha de cada etiqueta. Solo cuentan las que tienen cara
* de versión: números separados por puntos, con una v delante o sin ella
* (v13.1.1, 2.0). JSONFox tiene etiquetas viejas como «JSONFox911» o
* «Jsonv917», que no lo son y se ignoran.
*==================================================================
DEFINE CLASS Etiquetas AS Custom

    cFallo = ""
    *-- EtiquetaRepo de las que son versión.
    oLista = .NULL.

    PROCEDURE Init
        THIS.oLista = CREATEOBJECT("Collection")
    ENDPROC


    FUNCTION Leer(tcTexto)
        LOCAL loJson, loRaiz, loItem, loEtq, lnI, llBien, loErr, lcNombre

        THIS.cFallo = ""
        THIS.oLista = CREATEOBJECT("Collection")
        llBien = .F.
        TRY
            loJson = NEWOBJECT("JSONFox", "JsonFox.prg")
            loRaiz = loJson.Parse(tcTexto)
            llBien = !loJson.lError
            IF !llBien
                THIS.cFallo = "the tag list is not valid JSON: " + loJson.cLastError
            ENDIF
        CATCH TO loErr
            THIS.cFallo = "the tag list is not valid JSON: " + loErr.Message
        ENDTRY
        IF !llBien
            RETURN .F.
        ENDIF
        IF VARTYPE(loRaiz) <> "O" OR TYPE("loRaiz.Count") <> "N"
            THIS.cFallo = "the tag list is not a list"
            RETURN .F.
        ENDIF

        FOR lnI = 1 TO loRaiz.Count
            loItem = loRaiz.Item(lnI)
            IF TYPE("loItem.name") == "C" AND TYPE("loItem.commit.sha") == "C"
                lcNombre = ALLTRIM(loItem.name)
                IF THIS.EsVersion(lcNombre)
                    loEtq = CREATEOBJECT("EtiquetaRepo")
                    loEtq.cEtiqueta = lcNombre
                    loEtq.cVersion = THIS.SinV(lcNombre)
                    loEtq.cCommit = LOWER(ALLTRIM(loItem.commit.sha))
                    THIS.oLista.Add(loEtq)
                ENDIF
            ENDIF
        ENDFOR
        RETURN .T.
    ENDFUNC


    *-- La etiqueta de esa versión (con o sin v), o .NULL.
    FUNCTION Elegir(tcVersion)
        LOCAL loEtq, loUna, lnI
        loEtq = .NULL.
        FOR lnI = 1 TO THIS.oLista.Count
            loUna = THIS.oLista.Item(lnI)
            IF loUna.cVersion == THIS.SinV(tcVersion)
                loEtq = loUna
                EXIT
            ENDIF
        ENDFOR
        RETURN loEtq
    ENDFUNC


    *-- La versión más alta, o .NULL. si no hay ninguna.
    FUNCTION Ultima()
        LOCAL loEtq, loUna, lnI
        loEtq = .NULL.
        FOR lnI = 1 TO THIS.oLista.Count
            loUna = THIS.oLista.Item(lnI)
            IF ISNULL(loEtq)
                loEtq = loUna
            ELSE
                IF THIS.Comparar(loUna.cVersion, loEtq.cVersion) > 0
                    loEtq = loUna
                ENDIF
            ENDIF
        ENDFOR
        RETURN loEtq
    ENDFUNC


    *-- Las versiones, separadas por comas, para un mensaje.
    FUNCTION Todas()
        LOCAL lcTodas, lnI, loUna
        lcTodas = ""
        FOR lnI = 1 TO THIS.oLista.Count
            loUna = THIS.oLista.Item(lnI)
            lcTodas = lcTodas + IIF(EMPTY(lcTodas), "", ", ") + loUna.cVersion
        ENDFOR
        RETURN lcTodas
    ENDFUNC


    *-- 1 si tcA es más nueva, -1 si es más vieja, 0 si son la misma.
    *-- Por partes y como números: 13.10 es más nueva que 13.9.
    FUNCTION Comparar(tcA, tcB)
        LOCAL lnPartes, lnI, lnA, lnB, lnRes
        lnPartes = MAX(GETWORDCOUNT(tcA, "."), GETWORDCOUNT(tcB, "."))
        lnRes = 0
        FOR lnI = 1 TO lnPartes
            lnA = VAL(GETWORDNUM(tcA, lnI, "."))
            lnB = VAL(GETWORDNUM(tcB, lnI, "."))
            IF lnA <> lnB
                lnRes = IIF(lnA > lnB, 1, -1)
                EXIT
            ENDIF
        ENDFOR
        RETURN lnRes
    ENDFUNC


    *-- Números separados por puntos, con v delante o sin ella.
    FUNCTION EsVersion(tcTexto)
        LOCAL lcV
        lcV = THIS.SinV(tcTexto)
        RETURN !EMPTY(lcV) AND LEN(CHRTRAN(lcV, "0123456789.", "")) = 0 ;
            AND !(LEFT(lcV, 1) == ".") AND !(RIGHT(lcV, 1) == ".") AND !(".." $ lcV)
    ENDFUNC


    FUNCTION SinV(tcTexto)
        LOCAL lcV
        lcV = ALLTRIM(tcTexto)
        IF UPPER(LEFT(lcV, 1)) == "V"
            lcV = SUBSTR(lcV, 2)
        ENDIF
        RETURN lcV
    ENDFUNC

ENDDEFINE


DEFINE CLASS EtiquetaRepo AS Custom
    cEtiqueta = ""
    cVersion = ""
    cCommit = ""
ENDDEFINE
