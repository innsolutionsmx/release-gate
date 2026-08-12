<?php

/**
 * Gate: links internos — todo route('nombre') referenciado en las vistas
 * debe existir en el router. Detecta vistas apuntando a rutas muertas
 * (renderizarlas = 500). Excluye $request->route('param') (accessor).
 *
 * Vendoreado por /release-gate:init — NO editar a mano (drift: /release-gate:doctor).
 *
 * Uso: php scripts/gate-links.php  (exit 0 = ok, 1 = rutas rotas)
 */
$raiz = dirname(__DIR__);

exec('php '.escapeshellarg($raiz.'/artisan').' route:list --json 2>/dev/null', $salida, $codigo);
if ($codigo !== 0) {
    fwrite(STDERR, "No se pudo obtener route:list\n");
    exit(2);
}
$definidas = array_filter(array_column(json_decode(implode('', $salida), true) ?? [], 'name'));

$usadas = [];
$iterador = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($raiz.'/resources/views', FilesystemIterator::SKIP_DOTS)
);
foreach ($iterador as $archivo) {
    if (! str_ends_with($archivo->getFilename(), '.blade.php')) {
        continue;
    }
    $contenido = file_get_contents($archivo->getPathname());
    if (preg_match_all("/(?<!->)route\('([^']+)'/", $contenido, $m)) {
        foreach ($m[1] as $nombre) {
            $usadas[$nombre][] = substr($archivo->getPathname(), strlen($raiz) + 1);
        }
    }
}

$rotas = array_diff_key($usadas, array_flip($definidas));
if ($rotas === []) {
    echo 'OK: '.count($usadas)." rutas referenciadas en vistas, todas existen\n";
    exit(0);
}
foreach ($rotas as $nombre => $archivos) {
    echo "ROTA: route('$nombre') no existe — usada en: ".implode(', ', array_unique($archivos))."\n";
}
exit(1);
