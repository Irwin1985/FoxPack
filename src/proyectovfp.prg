*==================================================================
* proyectovfp.prg -- quitar de los .pjx de la carpeta lo que era de una
* librería que se acaba de borrar
*
* Idea de Irwin (25-09-2026). Sin esto, «foxpack remove» con el proyecto
* cerrado dejaba la entrada de lib\<librería>\... en el .pjx, y al abrir
* el proyecto VFP preguntaba por el fichero («Locate File»); con Ignore,
* la entrada se quedaba apuntando a la carpeta de VFP.
*
* Un .pjx es una tabla. Cada fichero es un registro, con la ruta en NAME:
* relativa a la carpeta del proyecto, en minúsculas y acabada en CHR(0)
* (medido: "lib\jsonfox\jsonfox.prg" + CHR(0), TYPE "P"). Se marcan como
* borrados con DELETE y sin PACK: VFP ya deja registros borrados en un
* .pjx y los ignora, y sin PACK no se reescribe el fichero.
*
* Se abre EXCLUSIVE. Si el proyecto está abierto en el IDE no se puede,
* y entonces no hace falta: con el proyecto abierto no sale ningún
* diálogo, y Ctrl+F7 de FoxForge (0.3.22 en adelante) saca del proyecto
* lo que foxpack.lock ya no nombra. Se dice y se sigue.
*==================================================================

DEFINE CLASS ProyectoVfp AS Custom

    *-- Tras Quitar: los .pjx que no se pudieron abrir, uno por línea.
    cOcupados = ""

    *-- Quita de cada .pjx de tcCarpeta las entradas que caen dentro de
    *-- lib\<tcNombre>\. Devuelve cuántas quitó.
    FUNCTION Quitar(tcCarpeta, tcNombre)
        LOCAL lcCarpeta, lcPrefijo, lnQuitadas, lnI, lnN, lcPjx, lcRuta, lnArea, loErr, llAbierto
        LOCAL ARRAY laPjx[1]

        THIS.cOcupados = ""
        lcCarpeta = LOWER(ADDBS(tcCarpeta))
        lcPrefijo = lcCarpeta + "lib\" + LOWER(tcNombre) + "\"
        lnQuitadas = 0
        lnArea = SELECT()

        lnN = ADIR(laPjx, lcCarpeta + "*.pjx")
        FOR lnI = 1 TO lnN
            lcPjx = lcCarpeta + LOWER(laPjx[lnI, 1])
            llAbierto = .F.
            TRY
                USE (lcPjx) IN 0 AGAIN EXCLUSIVE ALIAS foxpack_pjx
                llAbierto = .T.
            CATCH TO loErr
                THIS.cOcupados = THIS.cOcupados + JUSTFNAME(lcPjx) + CHR(13)
            ENDTRY
            IF !llAbierto
                LOOP
            ENDIF
            SELECT foxpack_pjx
            SCAN FOR !DELETED() AND !(foxpack_pjx.TYPE == "H")
                lcRuta = LOWER(ALLTRIM(CHRTRAN(foxpack_pjx.NAME, CHR(0), "")))
                IF !(":" $ lcRuta) AND !(LEFT(lcRuta, 2) == "\\")
                    lcRuta = lcCarpeta + lcRuta
                ENDIF
                IF LEFT(lcRuta, LEN(lcPrefijo)) == lcPrefijo
                    DELETE
                    lnQuitadas = lnQuitadas + 1
                ENDIF
            ENDSCAN
            USE IN SELECT("foxpack_pjx")
        ENDFOR

        SELECT (lnArea)
        RETURN lnQuitadas
    ENDFUNC

ENDDEFINE
