*==================================================================
* remoto.prg -- todo lo que FoxPack trae de fuera pasa por aquí
*
* Tres cosas, y de dos sitios posibles:
*
*   el índice          index.json del repo Irwin1985/foxpack-index
*   las etiquetas      de un repo, con el commit de cada una (API de GitHub)
*   un fichero         de un repo, en un commit concreto (raw)
*
* De GitHub, o de una carpeta local que lo imita si la variable de
* entorno FOXPACK_REMOTE apunta a ella. Así las pruebas no tocan la red
* y no dependen de que GitHub conteste:
*
*   <FOXPACK_REMOTE>\index.json
*   <FOXPACK_REMOTE>\repos\<dueño>\<repo>\tags.json       (como la API)
*   <FOXPACK_REMOTE>\repos\<dueño>\<repo>\<commit>\<ruta>  (como raw)
*
* Los ficheros se guardan con los bytes que llegan: ResponseBody es un
* varbinary (VARTYPE "Q") y STRTOFILE lo escribe tal cual. Medido el
* 25-09-2026: JsonFox.prg bajado así tiene el mismo SHA-256 que el de la
* etiqueta. Nada pasa por una cadena convertida.
*
* La API de GitHub sin token da 60 peticiones por hora: la usan add y
* update (una por librería). restore no la toca, baja por commit.
*==================================================================

#DEFINE URL_INDICE  "https://raw.githubusercontent.com/Irwin1985/foxpack-index/main/index.json"
#DEFINE URL_API     "https://api.github.com/repos/"
#DEFINE URL_RAW     "https://raw.githubusercontent.com/"

DEFINE CLASS Remoto AS Custom

    *-- El último fallo, en texto; vacío si todo fue bien.
    cFallo = ""
    *-- .T. si el último fallo fue un «no existe» (404): para que quien
    *-- llama distinga «esa librería no existe» de «no hay red».
    lNoExiste = .F.
    *-- La carpeta que imita GitHub; vacía, GitHub de verdad.
    cBase = ""

    PROCEDURE Init
        LOCAL lcBase
        lcBase = ALLTRIM(GETENV("FOXPACK_REMOTE"))
        IF !EMPTY(lcBase)
            THIS.cBase = ADDBS(lcBase)
        ENDIF
    ENDPROC


    *-- El texto de index.json; vacío si no se pudo traer.
    FUNCTION TextoIndice()
        IF EMPTY(THIS.cBase)
            RETURN THIS.PedirTexto(URL_INDICE, .F.)
        ENDIF
        RETURN THIS.LeerLocal(THIS.cBase + "index.json")
    ENDFUNC


    *-- Las etiquetas de un repo, como las da la API: una lista JSON con
    *-- name y commit.sha de cada una.
    FUNCTION TextoEtiquetas(tcRepo)
        IF !THIS.RepoValido(tcRepo)
            RETURN ""
        ENDIF
        IF EMPTY(THIS.cBase)
            RETURN THIS.PedirTexto(URL_API + tcRepo + "/tags?per_page=100", .T.)
        ENDIF
        RETURN THIS.LeerLocal(THIS.cBase + "repos\" + CHRTRAN(tcRepo, "/", "\") + "\tags.json")
    ENDFUNC


    *-- El texto de un fichero de un repo en un commit (foxpack.json).
    FUNCTION TextoFichero(tcRepo, tcCommit, tcRuta)
        IF !THIS.RepoValido(tcRepo) OR !THIS.RutaValida(tcRuta)
            RETURN ""
        ENDIF
        IF EMPTY(THIS.cBase)
            RETURN THIS.PedirTexto(URL_RAW + tcRepo + "/" + tcCommit + "/" + tcRuta, .F.)
        ENDIF
        RETURN THIS.LeerLocal(THIS.RutaLocal(tcRepo, tcCommit, tcRuta))
    ENDFUNC


    *-- Baja un fichero de un repo en un commit y lo deja en tcDestino con
    *-- sus bytes. .T. si quedó escrito.
    FUNCTION BajarFichero(tcRepo, tcCommit, tcRuta, tcDestino)
        LOCAL lqDatos, llBien, loErr
        LOCAL ARRAY laEsta[1]

        THIS.cFallo = ""
        THIS.lNoExiste = .F.
        IF !THIS.RepoValido(tcRepo) OR !THIS.RutaValida(tcRuta)
            RETURN .F.
        ENDIF

        llBien = .F.
        IF EMPTY(THIS.cBase)
            lqDatos = THIS.Pedir(URL_RAW + tcRepo + "/" + tcCommit + "/" + tcRuta, .F.)
            IF !ISNULL(lqDatos)
                TRY
                    STRTOFILE(lqDatos, tcDestino)
                    llBien = .T.
                CATCH TO loErr
                    THIS.cFallo = "cannot write " + tcDestino + ": " + loErr.Message
                ENDTRY
            ENDIF
        ELSE
            IF ADIR(laEsta, THIS.RutaLocal(tcRepo, tcCommit, tcRuta)) = 0
                THIS.lNoExiste = .T.
                THIS.cFallo = "not found: " + tcRepo + "/" + tcCommit + "/" + tcRuta
            ELSE
                TRY
                    COPY FILE (THIS.RutaLocal(tcRepo, tcCommit, tcRuta)) TO (tcDestino)
                    llBien = .T.
                CATCH TO loErr
                    THIS.cFallo = "cannot copy " + tcRuta + ": " + loErr.Message
                ENDTRY
            ENDIF
        ENDIF
        RETURN llBien
    ENDFUNC


    *-- «dueño/repo», con los caracteres que admite GitHub y nada más.
    FUNCTION RepoValido(tcRepo)
        LOCAL lcRepo, llBien
        lcRepo = ALLTRIM(tcRepo)
        llBien = OCCURS("/", lcRepo) = 1 AND !(LEFT(lcRepo, 1) == "/") AND !(RIGHT(lcRepo, 1) == "/") ;
            AND LEN(CHRTRAN(LOWER(lcRepo), "abcdefghijklmnopqrstuvwxyz0123456789-_./", "")) = 0 ;
            AND !(".." $ lcRepo)
        IF !llBien
            THIS.cFallo = "not a GitHub repository (user/repo): " + lcRepo
        ENDIF
        RETURN llBien
    ENDFUNC


    *-- Una ruta dentro del repo: relativa y sin «..». Un foxpack.json no
    *-- puede escribir fuera de lib\<librería>\.
    FUNCTION RutaValida(tcRuta)
        LOCAL lcRuta, llBien
        lcRuta = CHRTRAN(ALLTRIM(tcRuta), "\", "/")
        llBien = !EMPTY(lcRuta) AND !(LEFT(lcRuta, 1) == "/") AND !(":" $ lcRuta) ;
            AND !(".." $ lcRuta)
        IF !llBien
            THIS.cFallo = "not a valid path inside a repository: " + tcRuta
        ENDIF
        RETURN llBien
    ENDFUNC


    PROTECTED FUNCTION RutaLocal(tcRepo, tcCommit, tcRuta)
        RETURN THIS.cBase + "repos\" + CHRTRAN(tcRepo, "/", "\") + "\" + tcCommit + "\" + ;
            CHRTRAN(tcRuta, "/", "\")
    ENDFUNC


    PROTECTED FUNCTION LeerLocal(tcRuta)
        LOCAL lcTexto
        LOCAL ARRAY laEsta[1]
        THIS.cFallo = ""
        THIS.lNoExiste = .F.
        IF ADIR(laEsta, tcRuta) = 0
            THIS.lNoExiste = .T.
            THIS.cFallo = "not found: " + tcRuta
            RETURN ""
        ENDIF
        lcTexto = FILETOSTR(tcRuta)
        RETURN STRCONV(lcTexto, 11)
    ENDFUNC


    *-- El texto de una URL, de UTF-8 a la página de códigos de VFP.
    PROTECTED FUNCTION PedirTexto(tcUrl, tlApi)
        LOCAL lqDatos
        lqDatos = THIS.Pedir(tcUrl, tlApi)
        IF ISNULL(lqDatos)
            RETURN ""
        ENDIF
        RETURN STRCONV(CAST(lqDatos AS M), 11)
    ENDFUNC


    *-- Los bytes de una URL, o .NULL. con el motivo en cFallo.
    PROTECTED FUNCTION Pedir(tcUrl, tlApi)
        LOCAL loHttp, lqDatos, lnEstado, loErr

        THIS.cFallo = ""
        THIS.lNoExiste = .F.
        lqDatos = .NULL.
        lnEstado = 0
        TRY
            loHttp = CREATEOBJECT("WinHttp.WinHttpRequest.5.1")
            loHttp.SetTimeouts(10000, 10000, 15000, 60000)
            loHttp.Open("GET", tcUrl, .F.)
            loHttp.SetRequestHeader("User-Agent", "FoxPack")
            IF tlApi
                loHttp.SetRequestHeader("Accept", "application/vnd.github+json")
            ENDIF
            loHttp.Send()
            lnEstado = loHttp.Status
            IF lnEstado = 200
                lqDatos = loHttp.ResponseBody
            ENDIF
        CATCH TO loErr
            THIS.cFallo = "cannot reach " + tcUrl + ": " + ALLTRIM(loErr.Message)
        ENDTRY

        DO CASE
        CASE !EMPTY(THIS.cFallo)
        CASE lnEstado = 404
            THIS.lNoExiste = .T.
            THIS.cFallo = "not found: " + tcUrl
        CASE lnEstado = 403 AND tlApi
            THIS.cFallo = "GitHub refused the request (403): the API allows 60 requests " + ;
                "per hour without a token. Try again later."
        CASE lnEstado <> 200
            THIS.cFallo = "HTTP " + TRANSFORM(lnEstado) + " from " + tcUrl
        ENDCASE
        RETURN lqDatos
    ENDFUNC

ENDDEFINE
