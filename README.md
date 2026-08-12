# release-gate

Compuerta de calidad determinista para código escrito por agentes. Capa 1 que
**bloquea** — pasa o no pasa, sin opiniones — con **trinquete**: la realidad de
hoy se congela y solo se permite mejorar.

- Scripts **idénticos entre proyectos**; todo dato del proyecto vive en
  `.gate/baseline.json` (schema 1).
- Dos perfiles: **medida** (sistemas con dominio → + PHPStan n8 con trinquete) y
  **landing** (sitios → + innerHTML, links, headers, Lighthouse).
- Los scripts se **vendorean** al repo: el gate corre en CI y en máquinas sin el
  plugin; el drift lo custodia `/release-gate:doctor` por checksum.

Concepto completo: [docs/que-es-y-por-que.md](docs/que-es-y-por-que.md).

## Instalación

```
/plugin marketplace add innsolutionsmx/release-gate
/plugin install release-gate@release-gate
```

## Uso

| Comando | Qué hace |
|---|---|
| `/release-gate:init` | Instala el gate en el repo: perfil (confirmado por humano), scripts vendoreados, baseline medido y congelado, job de CI |
| `/release-gate:run` | Corre el gate e interpreta las fallas |
| `/release-gate:ratchet` | Aprieta el trinquete donde la realidad mejoró (nunca afloja) |
| `/release-gate:deploy-check` | Headers + Lighthouse contra el sitio vivo (la 1.ª corrida congela mínimos) |
| `/release-gate:doctor` | Salud de la instalación: baseline, drift, herramientas, CI |

Checks por perfil, schema del baseline y snippet de CI:
[docs/referencia.md](docs/referencia.md).

## Requisitos del repo consumidor

Laravel con `vendor/bin/pint` (y `vendor/bin/phpstan` para perfil medida),
`gitleaks` en PATH, `composer` y `npm`. Para el post-deploy: Chrome
(`CHROME_PATH`) y red hacia el sitio desplegado.

## Desarrollo

Reglas del repo (plan primero, push a main = release, gate del manifest):
[docs/desarrollo-y-releases.md](docs/desarrollo-y-releases.md).
