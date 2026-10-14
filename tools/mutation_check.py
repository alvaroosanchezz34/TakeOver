#!/usr/bin/env python3
"""
Comprobación por mutación de las salvaguardas críticas.

Rompe A PROPÓSITO, de una en una, protecciones de seguridad/economía y exige que la
suite de tests FALLE. Si una mutación "sobrevive" (los tests siguen en verde), esa
salvaguarda no está realmente cubierta por las pruebas.

Uso:  python3 tools/mutation_check.py [filtro]
Requiere `lune` en el PATH (ver tools/setup.sh). No modifica el árbol de trabajo:
cada mutación se aplica sobre una copia temporal.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (descripción, fichero, fragmento original (debe aparecer 1 vez), sustituto)
MUTATIONS = [
    (
        "una oferta ya ejecutada se puede ejecutar de nuevo",
        "src/server/Core/TradeEngine.luau",
        'if offer.state ~= "pending" then\n\t\treturn Result.err("OFFER_NOT_PENDING", { state = offer.state })\n\tend',
        "",
    ),
    (
        "se ignora la revisión de la estructura de propiedad (oferta obsoleta)",
        "src/server/Core/TradeEngine.luau",
        "if company.cap.rev ~= offer.capRev then",
        "if false then",
    ),
    (
        "no se revierte una ejecución que falla a medias",
        "src/server/Core/TradeEngine.luau",
        "self:_rollback(snap, buyer, seller, company)\n\t\tlocal code",
        "local code",
    ),
    (
        "se acepta sin comprobar los fondos del comprador",
        "src/server/Core/TradeEngine.luau",
        "if not d.ledger:canAfford(buyer, offer.price) then\n\t\t-- Sin fondos no se cierra",
        "if false then\n\t\t-- Sin fondos no se cierra",
    ),
    (
        "no hay impuesto de venta",
        "src/server/Core/TradeEngine.luau",
        "local tax = Money.mulBps(offer.price, Balance.SaleTaxBps)",
        "local tax = 0",
    ),
    (
        "no se valida la banda de precios al ofertar",
        "src/server/Core/TradeEngine.luau",
        "if p.price < min or p.price > max then",
        "if false then",
    ),
    (
        "no se exige confirmación en operaciones importantes",
        "src/server/Core/TradeEngine.luau",
        "and confirm ~= true then\n\t\treturn Result.err(\"CONFIRMATION_REQUIRED\", {\n\t\t\tprice = offer.price,",
        "and false then\n\t\treturn Result.err(\"CONFIRMATION_REQUIRED\", {\n\t\t\tprice = offer.price,",
    ),
    (
        "cualquiera puede aceptar la oferta de otro",
        "src/server/Core/TradeEngine.luau",
        "if offer.sellerId ~= seller.id then\n\t\treturn Result.err(\"NOT_YOUR_OFFER\")\n\tend\n\tif offer.state ~= \"pending\" then",
        "if false then\n\t\treturn Result.err(\"NOT_YOUR_OFFER\")\n\tend\n\tif offer.state ~= \"pending\" then",
    ),
    (
        "se pueden vender participaciones inexistentes",
        "src/shared/Economy/Ownership.luau",
        "if available < bps then",
        "if false then",
    ),
    (
        "el reparto de dividendos pierde céntimos de redondeo",
        "src/shared/Economy/Ownership.luau",
        "for i = 1, leftover do",
        "for i = 1, 0 do",
    ),
    (
        "se permite gastar más dinero del que se tiene",
        "src/server/Core/Ledger.luau",
        "if before < amount then",
        "if false then",
    ),
    (
        "un servidor puede escribir sin tener el bloqueo de sesión",
        "src/server/Core/ProfileStore.luau",
        "if type(old) ~= \"table\" or old.lock == nil or old.lock.jobId ~= self._jobId then\n\t\t\t\t\tlockLost = true",
        "if type(old) ~= \"table\" then\n\t\t\t\t\tlockLost = true",
    ),
    (
        "dos servidores pueden cargar el mismo perfil a la vez",
        "src/server/Core/ProfileStore.luau",
        "if now - (old.lock.t or 0) < self._lockTimeout then",
        "if false then",
    ),
    (
        "un tick atrasado acredita todo el tiempo perdido",
        "src/server/Core/IncomeEngine.luau",
        "dt = math.clamp(dt, 0, Balance.MaxTickDelta)",
        "dt = math.max(dt, 0)",
    ),
    (
        "cualquiera puede gestionar una empresa ajena",
        "src/server/Core/CompanyOps.luau",
        "if Ownership.manager(company.cap, company.founderId) ~= session.id then",
        "if false then",
    ),
    (
        "la validación de red acepta NaN e infinito",
        "src/shared/Util/Validate.luau",
        "if not isFinite(value) then",
        "if false then",
    ),
    (
        "el fundador puede quedarse sin gestor viable",
        "src/shared/Economy/Ownership.luau",
        "if Ownership.stake(sim, manager) < Governance.MinManagerBps then",
        "if false then",
    ),
    (
        "la Bolsa permite superar el cupo por jugador",
        "src/server/Core/TradeEngine.luau",
        "if owned + bps > Balance.Npc.PerPlayerCapBps then",
        "if false then",
    ),
]


def main() -> int:
    flt = sys.argv[1] if len(sys.argv) > 1 else None
    survivors = []
    ran = 0
    for desc, rel, old, new in MUTATIONS:
        if flt and flt not in desc and flt not in rel:
            continue
        ran += 1
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp) / "repo"
            shutil.copytree(
                ROOT,
                work,
                ignore=shutil.ignore_patterns(".git", ".tools", "build", "sourcemap.json", "node_modules"),
            )
            target = work / rel
            text = target.read_text(encoding="utf-8")
            if text.count(old) != 1:
                print(f"?  FRAGMENTO NO ENCONTRADO ({text.count(old)} veces): {desc}  [{rel}]")
                survivors.append(desc + " (fragmento no encontrado: actualiza la herramienta)")
                continue
            target.write_text(text.replace(old, new), encoding="utf-8")
            result = subprocess.run(
                ["lune", "run", "tests/run"], cwd=work, capture_output=True, text=True, timeout=300
            )
            killed = result.returncode != 0
            print(f"{'✔ detectada ' if killed else '✘ SOBREVIVE '} {desc}")
            if not killed:
                survivors.append(desc)
    print()
    print(f"{ran - len(survivors)}/{ran} mutaciones detectadas por los tests")
    if survivors:
        print("Salvaguardas sin cubrir:")
        for s in survivors:
            print("  -", s)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
