*==================================================================
* huella.prg -- el SHA-256 de un fichero o de una cadena
*
* VFP no trae ningún hash criptográfico, y la CryptoAPI de Windows sí:
* advapi32.dll, con el proveedor PROV_RSA_AES, que es el que sabe
* SHA-256 (el proveedor por defecto no). Está en todos los Windows desde
* XP SP3, así que no añade nada que desplegar.
*
* El fichero se lee con FILETOSTR, que no convierte nada: se hashean los
* bytes que hay en el disco, que son los que verify volverá a medir.
*
* Las funciones se declaran con alias propios (fp_*) para no pisar un
* DECLARE con el mismo nombre que haga otro código del proceso.
*==================================================================

#DEFINE PROV_RSA_AES          24
#DEFINE CRYPT_VERIFYCONTEXT   -268435456
#DEFINE CALG_SHA_256          32780
#DEFINE HP_HASHVAL            2

DEFINE CLASS Huella AS Custom

    *-- El último fallo, en texto; vacío si todo fue bien.
    cFallo = ""

    PROCEDURE Init
        DECLARE INTEGER CryptAcquireContextA IN advapi32 AS fp_CryptAcquireContext ;
            INTEGER @phProv, INTEGER pszContainer, INTEGER pszProvider, ;
            INTEGER dwProvType, INTEGER dwFlags
        DECLARE INTEGER CryptCreateHash IN advapi32 AS fp_CryptCreateHash ;
            INTEGER hProv, INTEGER Algid, INTEGER hKey, INTEGER dwFlags, INTEGER @phHash
        DECLARE INTEGER CryptHashData IN advapi32 AS fp_CryptHashData ;
            INTEGER hHash, STRING pbData, INTEGER dwDataLen, INTEGER dwFlags
        DECLARE INTEGER CryptGetHashParam IN advapi32 AS fp_CryptGetHashParam ;
            INTEGER hHash, INTEGER dwParam, STRING @pbData, INTEGER @pdwDataLen, INTEGER dwFlags
        DECLARE INTEGER CryptDestroyHash IN advapi32 AS fp_CryptDestroyHash ;
            INTEGER hHash
        DECLARE INTEGER CryptReleaseContext IN advapi32 AS fp_CryptReleaseContext ;
            INTEGER hProv, INTEGER dwFlags
    ENDPROC


    *-- El SHA-256 de un fichero, en hexadecimal y minúsculas. Vacío si no
    *-- se pudo leer o hashear; el motivo queda en cFallo.
    FUNCTION DeFichero(tcRuta)
        LOCAL lcDatos, llLeido, loErr
        LOCAL ARRAY laEsta[1]

        THIS.cFallo = ""
        IF ADIR(laEsta, tcRuta) = 0
            THIS.cFallo = "not found: " + tcRuta
            RETURN ""
        ENDIF
        llLeido = .F.
        TRY
            lcDatos = FILETOSTR(tcRuta)
            llLeido = .T.
        CATCH TO loErr
            THIS.cFallo = "cannot read " + tcRuta + ": " + loErr.Message
        ENDTRY
        IF !llLeido
            RETURN ""
        ENDIF
        RETURN THIS.DeCadena(lcDatos)
    ENDFUNC


    *-- El SHA-256 de una cadena, tomada como bytes.
    FUNCTION DeCadena(tcDatos)
        LOCAL lnProv, lnHash, lcBuffer, lnLargo, lcHex

        THIS.cFallo = ""
        lcHex = ""
        lnProv = 0
        lnHash = 0

        IF fp_CryptAcquireContext(@lnProv, 0, 0, PROV_RSA_AES, CRYPT_VERIFYCONTEXT) = 0
            THIS.cFallo = "CryptAcquireContext failed"
            RETURN ""
        ENDIF

        DO CASE
        CASE fp_CryptCreateHash(lnProv, CALG_SHA_256, 0, 0, @lnHash) = 0
            THIS.cFallo = "CryptCreateHash failed"
        CASE LEN(tcDatos) > 0 AND fp_CryptHashData(lnHash, tcDatos, LEN(tcDatos), 0) = 0
            THIS.cFallo = "CryptHashData failed"
        OTHERWISE
            lcBuffer = REPLICATE(CHR(0), 32)
            lnLargo = 32
            IF fp_CryptGetHashParam(lnHash, HP_HASHVAL, @lcBuffer, @lnLargo, 0) = 0
                THIS.cFallo = "CryptGetHashParam failed"
            ELSE
                lcHex = LOWER(STRCONV(LEFT(lcBuffer, lnLargo), 15))
            ENDIF
        ENDCASE

        IF lnHash <> 0
            =fp_CryptDestroyHash(lnHash)
        ENDIF
        =fp_CryptReleaseContext(lnProv, 0)
        RETURN lcHex
    ENDFUNC

ENDDEFINE
