<?php

namespace Gate\PHPStan\Rules;

use Illuminate\Database\Eloquent\Model;
use PHPStan\Analyser\Scope;
use PHPStan\Type\ObjectType;
use PHPStan\Type\Type;

/**
 * Helper compartido por las reglas anti-queries: reconocer un Controller
 * y reconocer un Model de Eloquent.
 */
trait ControllerScope
{
    private function enControlador(Scope $scope): bool
    {
        $clase = $scope->getClassReflection();

        return $clase !== null && str_starts_with($clase->getName(), 'App\\Http\\Controllers\\');
    }

    private function esModelo(Type $tipo): bool
    {
        return (new ObjectType(Model::class))->isSuperTypeOf($tipo)->yes();
    }
}
