# Guía para desarrolladores — trabajar en un repo con Release Gate

Este documento es para vos: desarrollador que trabaja (vía Claude Code) en un
repo de la casa que tiene el Release Gate instalado. No necesitás instalar nada
para que el gate funcione — todo viaja en el repo con `git pull`. Acá está qué
es, qué vas a ver, y qué hacer en cada caso.

## Qué es el gate

Una compuerta de calidad **determinista**: pasa o no pasa, sin opiniones. Corre
los mismos checks en tu máquina y en CI (formato, análisis estático, secretos,
dependencias, seguridad de vistas). La CI bloquea el merge si el gate no pasa.

La pieza clave es el **trinquete**: el archivo `.gate/baseline.json` congela la
realidad del repo el día que se instaló el gate. Desde ahí, el código solo puede
**mantenerse o mejorar** — nunca empeorar. Cuando la realidad mejora, el baseline
se aprieta y esa mejora queda protegida para siempre.

## Qué vas a ver en tu sesión de Claude Code

**1. El tablero, al abrir cada sesión.** Un hook imprime el estado del gate
directo al contexto de tu Claude:

```
Release Gate — perfil medida (14 checks)
  Ultimo gate: 2026-08-12 14:31 commit a1b2c3d -> APROBADO

  Herramienta    Congelado   En archivo   Realidad
  PHPStan              904          903   requiere analisis
  ...

  SE PUEDE APRETAR: PHPStan 903 < 904 congeladas -> /release-gate:ratchet
```

Tu Claude lo lee solo: sabe el perfil del repo, si la evidencia está fresca y si
hay una mejora esperando a congelarse.

**2. El guard de push.** Un push a `dev` o `main` solo pasa si existe una
corrida **verde** del gate sobre el commit exacto que estás pusheando, con el
árbol limpio. Si no, el push se deniega con el motivo y el fix. No es un
castigo: es la garantía de que a `dev` nunca llega código que la CI va a
rebotar 10 minutos después.

**3. El bloque en `CLAUDE.md`.** El criterio del gate, en el contexto de tu
Claude en cada sesión.

## El flujo de trabajo diario

1. Trabajás normal en tu rama. El gate no te molesta.
2. Antes de pushear a `dev`: corré el gate — `./scripts/gate-run.sh` (o
   `/release-gate:run` si tenés el plugin). Eso escribe la evidencia local que
   el guard exige.
3. **Si el gate bloquea, se arregla la CAUSA**: formatear, tipar, sacar el flujo
   contaminado, subir la dependencia. El propio reporte dice qué falló y dónde.
4. Si el tablero dice **SE PUEDE APRETAR**, avisá o corré
   `/release-gate:ratchet`: tu mejora se congela y ya nadie la puede deshacer.

## Las reglas de oro

- **El baseline NUNCA se edita para que el gate pase.** Es la única regla
  inquebrantable. El baseline solo se toca en una dirección — apretándolo — y
  solo vía `/release-gate:ratchet`, cuando la realidad ya mejoró.
- **Los scripts `scripts/gate-*.sh` y los hooks no se editan a mano.** Son
  idénticos en todos los repos de la casa; todo dato del proyecto vive en
  `.gate/baseline.json`. `/release-gate:doctor` delata cualquier edición por
  checksum.
- `GATE_SKIP=1` delante de un push lo deja pasar sin evidencia. Es para
  emergencias reales (hotfix con CI caída), queda registrado en el transcript, y
  la CI va a correr el gate igual. Si lo necesitás seguido, algo anda mal:
  avisá.

## Preguntas rápidas

**Me bloqueó el push y yo no toqué nada raro.** Leé el motivo del bloqueo: casi
siempre es "sin evidencia" (no corriste el gate sobre este commit) o "árbol
sucio" (tenés cambios sin commitear). Corré `./scripts/gate-run.sh` y volvé a
pushear.

**Cloné el repo en una máquina nueva y el primer push me pidió correr el
gate.** Correcto: la evidencia es local por desarrollador (no viaja en git).
Una corrida y listo.

**El gate falla por algo que yo no escribí.** Puede pasar (una dependencia con
advisory nuevo, por ejemplo). Igual se arregla antes de pushear — el gate
protege el repo, no reparte culpas.

**¿Qué es cada archivo?** `.gate/baseline.json` = números congelados del repo;
`*-baseline.{neon,xml,yaml}` = perdones puntuales de cada herramienta (solo se
achican); `.gate/last-run.json` = tu evidencia local (gitignored).

## El plugin (opcional, recomendado)

El gate te funciona sin instalar nada. El plugin agrega los comandos guiados —
`/release-gate:run` interpreta las fallas y te guía al fix real,
`/release-gate:ratchet` sabe apretar los baselines sin romperlos. Se instala una
sola vez, a nivel usuario, dentro de Claude Code:

```
/plugin marketplace add innsolutionsmx/release-gate
/plugin install release-gate@release-gate
```

(y reiniciá Claude Code).

**Herramientas que tu máquina necesita** (las mismas que ya usa el repo):
`composer`, `npm`, `gitleaks` en PATH; el resto (`pint`, `phpstan`, `psalm`,
etc.) viene por composer en el propio repo. En Windows, todo esto corre dentro
de WSL2, igual que el resto del stack de la casa.

---

Detalle técnico completo (checks por perfil, schema del baseline, contrato de
hooks): [referencia.md](referencia.md). El porqué del diseño:
[que-es-y-por-que.md](que-es-y-por-que.md).
