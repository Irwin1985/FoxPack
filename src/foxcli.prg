*==================================================================
* foxcli.prg -- la clase base de los comandos de foxpack
*
* Es de FoxCli: no la cambies. Tus comandos van en main.prg, en la
* clase que hereda de esta (AS FoxCliCommand OF foxcli.prg). Aquí vive
* lo que el host necesita en cada comando: THIS.oCon, THIS.oArgs y
* Console, la forma corta de THIS.oCon.
*
* Cuando una versión nueva de FoxForge la cambie, al compilar (Ctrl+F7)
* te ofrecerá actualizarla. La línea de abajo es su versión.
*
* FOXCLI-BASE 1
*==================================================================

DEFINE CLASS FoxCliCommand AS Session

    *-- Los pone el host antes de llamar a cada comando.
    oCon  = .NULL.
    oArgs = .NULL.

    *-- Console es THIS.oCon con un nombre corto: Console.WriteLine("Hola")
    *-- es THIS.oCon.WriteLine("Hola"), con los mismos métodos. Vale en
    *-- todo el programa, también en un PROCEDURE suelto o en otra clase.
    *--
    *-- Nace aquí: el host pone oCon antes de llamar al comando, y este
    *-- assign la publica. PUBLIC y no PRIVATE porque el host llama al
    *-- comando directamente, sin código VFP delante que pudiera declarar
    *-- una PRIVATE; cada ejecución de la CLI es un proceso nuevo, así que
    *-- no se queda nada colgado. No declares tú otra Console LOCAL: la
    *-- taparía en ese método.
    PROTECTED PROCEDURE oCon_Assign(toCon)
        THIS.oCon = toCon
        PUBLIC Console
        Console = toCon
    ENDPROC

ENDDEFINE
