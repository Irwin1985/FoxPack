*--------------------------------------------------------------------------
* FoxPackProofTests.prg -- las piezas de FoxPack sin la CLI. Runner: FoxProof.
*
*   foxproof run --prg tests\FoxPackProofTests.prg --format console
*
* Huella: el SHA-256 contra vectores conocidos, y los bytes de un fichero
*   CP1252 tal cual están en el disco.
* Candado: foxpack.lock de ida y vuelta, con las mayúsculas y el punto de
*   «JsonFox.prg» intactos (por eso el formato usa listas y no claves), un
*   fichero que sale igual cada vez, y los casos rotos.
*
* FoxProof compila el .prg dentro de un EXECSCRIPT: rutas absolutas en Root().
*--------------------------------------------------------------------------

DEFINE CLASS HuellaTests AS Custom

    oHuella = .NULL.
    cTmp = ""

    FUNCTION Root()
        RETURN "C:\Desarrollo\IrwinRodriguez.dev\FoxPack\"
    ENDFUNC

    PROCEDURE SetUp
        SET PROCEDURE TO (THIS.Root() + "src\huella.prg") ADDITIVE
        THIS.oHuella = CREATEOBJECT("Huella")
        THIS.cTmp = ADDBS(SYS(2023)) + "foxpack-proof-" + SYS(2015) + "\"
        MD (THIS.cTmp)
    ENDPROC

    PROCEDURE TearDown
        LOCAL lnI
        LOCAL ARRAY laF[1]
        FOR lnI = 1 TO ADIR(laF, THIS.cTmp + "*.*")
            ERASE (THIS.cTmp + laF[lnI, 1])
        ENDFOR
        TRY
            RD (THIS.cTmp)
        CATCH
        ENDTRY
    ENDPROC

    PROCEDURE TestAbc() HELP [Fact]
        __assert.Equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", ;
            THIS.oHuella.DeCadena("abc"))
    ENDPROC

    PROCEDURE TestCadenaVacia() HELP [Fact]
        __assert.Equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ;
            THIS.oHuella.DeCadena(""))
    ENDPROC

    PROCEDURE TestFicheroCp1252TalCual() HELP [Fact]
        *-- «ñandú» en CP1252 y un CRLF: si algo convirtiera los bytes, el
        *-- hash sería otro. El esperado lo calculó sha256sum.
        LOCAL lcRuta
        lcRuta = THIS.cTmp + "acentos.prg"
        STRTOFILE(CHR(241) + "and" + CHR(250) + CHR(13) + CHR(10), lcRuta)
        __assert.Equal("dc22f418a47f42dd48030f0da36a473d1f7fcd2b5242553529cdc49cb644c954", ;
            THIS.oHuella.DeFichero(lcRuta))
    ENDPROC

    PROCEDURE TestFicheroQueNoExiste() HELP [Fact]
        __assert.Equal("", THIS.oHuella.DeFichero(THIS.cTmp + "no-esta.prg"))
        __assert.True("not found" $ THIS.oHuella.cFallo, THIS.oHuella.cFallo)
    ENDPROC

ENDDEFINE


DEFINE CLASS CandadoTests AS Custom

    cTmp = ""

    FUNCTION Root()
        RETURN "C:\Desarrollo\IrwinRodriguez.dev\FoxPack\"
    ENDFUNC

    PROCEDURE SetUp
        LOCAL lcSrc
        lcSrc = THIS.Root() + "src"
        SET PATH TO (lcSrc) ADDITIVE
        SET PROCEDURE TO (THIS.Root() + "src\candado.prg") ADDITIVE
        THIS.cTmp = ADDBS(SYS(2023)) + "foxpack-proof-" + SYS(2015) + "\"
        MD (THIS.cTmp)
    ENDPROC

    PROCEDURE TearDown
        LOCAL lnI
        LOCAL ARRAY laF[1]
        FOR lnI = 1 TO ADIR(laF, THIS.cTmp + "*.*")
            ERASE (THIS.cTmp + laF[lnI, 1])
        ENDFOR
        TRY
            RD (THIS.cTmp)
        CATCH
        ENDTRY
    ENDPROC

    *-- Un candado con jsonfox (un fichero) y otra librería con dos.
    FUNCTION DosLibrerias()
        LOCAL loC, loLib
        loC = CREATEOBJECT("Candado")
        loLib = CREATEOBJECT("LibreriaCandado")
        loLib.cNombre = "jsonfox"
        loLib.cRepo = "Irwin1985/JSONFox"
        loLib.cVersion = "13.1"
        loLib.cCommit = "23c31883ec9067efc5ef44d819606d79826f5221"
        loLib.AnadirFichero("JsonFox.prg", "2FDF58C567F07BA12761A85FC782A1090E4765ACF1F986A2477A5CE2B27043C1")
        loC.oLibrerias.Add(loLib, "jsonfox")
        loLib = CREATEOBJECT("LibreriaCandado")
        loLib.cNombre = "otra"
        loLib.cRepo = "alguien/Otra"
        loLib.cVersion = "2.0.1"
        loLib.cCommit = "0123456789abcdef0123456789abcdef01234567"
        loLib.AnadirFichero("src/Otra.prg", "aa")
        loLib.AnadirFichero("otra.h", "bb")
        loC.oLibrerias.Add(loLib, "otra")
        RETURN loC
    ENDFUNC

    PROCEDURE TestSinFicheroNoHayNada() HELP [Fact]
        LOCAL loC
        loC = CREATEOBJECT("Candado")
        __assert.True(loC.Leer(THIS.cTmp + "foxpack.lock"), loC.cFallo)
        __assert.False(loC.lExiste)
        __assert.Equal(0, loC.oLibrerias.Count)
    ENDPROC

    PROCEDURE TestIdaYVuelta() HELP [Fact]
        LOCAL loC, loLeido, loLib, loF, lcRuta
        lcRuta = THIS.cTmp + "foxpack.lock"
        loC = THIS.DosLibrerias()
        __assert.True(loC.Escribir(lcRuta), loC.cFallo)

        loLeido = CREATEOBJECT("Candado")
        __assert.True(loLeido.Leer(lcRuta), loLeido.cFallo)
        __assert.True(loLeido.lExiste)
        __assert.Equal(2, loLeido.oLibrerias.Count)

        loLib = loLeido.Buscar("jsonfox")
        __assert.IsObject(loLib)
        __assert.Equal("Irwin1985/JSONFox", loLib.cRepo)
        __assert.Equal("13.1", loLib.cVersion)
        __assert.Equal("23c31883ec9067efc5ef44d819606d79826f5221", loLib.cCommit)
        loF = loLib.oFicheros.Item(1)
        *-- Con su mayúscula y su punto: como clave JSON se habría perdido.
        __assert.Equal("JsonFox.prg", loF.cRuta)
        __assert.Equal("2fdf58c567f07ba12761a85fc782a1090e4765acf1f986a2477a5ce2b27043c1", loF.cSha256)

        loLib = loLeido.Buscar("OTRA")
        __assert.IsObject(loLib)
        __assert.Equal(2, loLib.oFicheros.Count)
        loF = loLib.oFicheros.Item(1)
        __assert.Equal("src/Otra.prg", loF.cRuta)
    ENDPROC

    PROCEDURE TestSaleIgualCadaVez() HELP [Fact]
        *-- Leer y volver a escribir no cambia un byte: en git, un candado
        *-- sin cambios no sale en el diff.
        LOCAL loC, loLeido, lcRuta, lcPrimero
        lcRuta = THIS.cTmp + "foxpack.lock"
        loC = THIS.DosLibrerias()
        loC.Escribir(lcRuta)
        lcPrimero = FILETOSTR(lcRuta)
        loLeido = CREATEOBJECT("Candado")
        loLeido.Leer(lcRuta)
        loLeido.Escribir(lcRuta)
        __assert.Equal(lcPrimero, FILETOSTR(lcRuta))
        __assert.True('"lockVersion": 1' $ lcPrimero)
    ENDPROC

    PROCEDURE TestVacioSeEscribeYSeLee() HELP [Fact]
        LOCAL loC, lcRuta
        lcRuta = THIS.cTmp + "foxpack.lock"
        loC = CREATEOBJECT("Candado")
        __assert.True(loC.Escribir(lcRuta), loC.cFallo)
        loC = CREATEOBJECT("Candado")
        __assert.True(loC.Leer(lcRuta), loC.cFallo)
        __assert.Equal(0, loC.oLibrerias.Count)
    ENDPROC

    PROCEDURE TestEscapaComillasYBarras() HELP [Fact]
        LOCAL loC, loLib, lcRuta
        lcRuta = THIS.cTmp + "foxpack.lock"
        loC = CREATEOBJECT("Candado")
        loLib = CREATEOBJECT("LibreriaCandado")
        loLib.cNombre = "rara"
        loLib.cRepo = 'con"comillas\y\barras'
        loC.oLibrerias.Add(loLib, "rara")
        __assert.True(loC.Escribir(lcRuta), loC.cFallo)
        loC = CREATEOBJECT("Candado")
        __assert.True(loC.Leer(lcRuta), loC.cFallo)
        loLib = loC.Buscar("rara")
        __assert.Equal('con"comillas\y\barras', loLib.cRepo)
    ENDPROC

    PROCEDURE TestJsonRoto() HELP [Fact]
        LOCAL loC, lcRuta
        lcRuta = THIS.cTmp + "foxpack.lock"
        STRTOFILE('{"lockVersion": 1, "libraries": [', lcRuta)
        loC = CREATEOBJECT("Candado")
        __assert.False(loC.Leer(lcRuta))
        __assert.NotEmpty(loC.cFallo)
    ENDPROC

    PROCEDURE TestNombreRepetido() HELP [Fact]
        LOCAL loC, lcRuta
        lcRuta = THIS.cTmp + "foxpack.lock"
        STRTOFILE('{"lockVersion": 1, "libraries": [{"name": "a"}, {"name": "A"}]}', lcRuta)
        loC = CREATEOBJECT("Candado")
        __assert.False(loC.Leer(lcRuta))
        __assert.True("twice" $ loC.cFallo, loC.cFallo)
    ENDPROC

ENDDEFINE
