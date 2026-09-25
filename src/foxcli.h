*==================================================================
* foxcli.h -- los exit codes de foxpack
*
* Lo que DEVUELVE un comando es el exit code del proceso: lo que lee
* quien llama a la CLI desde un script (%ERRORLEVEL%, $LASTEXITCODE).
* Para ENSEÑAR un resultado se escribe con Console.WriteLine(); el
* RETURN es solo el código.
*
* Del 2 al 4 y el 130 son del host: no los devuelvas.
*    2  invocación mal formada       3  no se pudo activar el componente
*    4  fallo interno del host     130  cancelado con Ctrl+C
*
* Los tuyos van del 10 al 125. Decláralos aquí, con nombre:
*    #DEFINE EXIT_NOT_FOUND  10
* y en el comando: RETURN EXIT_NOT_FOUND
*==================================================================

#DEFINE EXIT_OK      0    && todo bien: lo mismo que RETURN .T., o no poner RETURN
#DEFINE EXIT_FAILED  1    && el comando falló: lo mismo que RETURN .F.
