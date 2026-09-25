*==================================================================
* foxcli.prg -- the base class of the foxpack commands
*
* It belongs to FoxCli: do not change it. Your commands go in main.prg,
* in the class that inherits from this one (AS FoxCliCommand OF
* foxcli.prg). What the host needs in every command lives here:
* THIS.oCon, THIS.oArgs and Console, the short form of THIS.oCon.
*
* When a new version of FoxForge changes it, building (Ctrl+F7) will
* offer to update it. The line below is its version.
*
* FOXCLI-BASE 1
*==================================================================

DEFINE CLASS FoxCliCommand AS Session

    *-- The host sets these before calling each command.
    oCon  = .NULL.
    oArgs = .NULL.

    *-- Console is THIS.oCon with a short name: Console.WriteLine("Hello")
    *-- is THIS.oCon.WriteLine("Hello"), with the same methods. It works
    *-- across the whole program, a loose PROCEDURE or another class too.
    *--
    *-- It is born here: the host sets oCon before calling the command,
    *-- and this assign publishes it. PUBLIC and not PRIVATE because the
    *-- host calls the command directly, with no VFP code in front that
    *-- could declare a PRIVATE; every run of the CLI is a new process, so
    *-- nothing is left hanging. Do not declare another LOCAL Console: it
    *-- would hide this one in that method.
    PROTECTED PROCEDURE oCon_Assign(toCon)
        THIS.oCon = toCon
        PUBLIC Console
        Console = toCon
    ENDPROC

ENDDEFINE
