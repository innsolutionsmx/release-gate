<?php

namespace Gate\PHPStan\Rules;

use PhpParser\Node;
use PhpParser\Node\Expr\StaticCall;
use PHPStan\Analyser\Scope;
use PHPStan\Rules\Rule;
use PHPStan\Rules\RuleErrorBuilder;
use PHPStan\Type\ObjectType;

/**
 * Prohíbe llamadas estáticas a Models desde Controllers: User::where(...),
 * AppSetting::get(...), NavItem::create(...). Son la puerta de entrada al
 * query builder y la forma más común de erosión del patrón
 * Controller -> FormRequest -> Action -> Model.
 *
 * Recibir un Model por route model binding SÍ está permitido: esta regla mira
 * LLAMADAS, no type hints (por eso existe, y por eso Deptrac quedó pragmático).
 *
 * @implements Rule<StaticCall>
 */
class NoModelStaticCallInControllerRule implements Rule
{
    use ControllerScope;

    public function getNodeType(): string
    {
        return StaticCall::class;
    }

    public function processNode(Node $node, Scope $scope): array
    {
        if (! $this->enControlador($scope)) {
            return [];
        }

        if (! $node->class instanceof Node\Name) {
            return [];
        }

        $clase = $scope->resolveName($node->class);

        if (! $this->esModelo(new ObjectType($clase))) {
            return [];
        }

        $metodo = $node->name instanceof Node\Identifier ? $node->name->toString() : 'método';

        return [
            RuleErrorBuilder::message(sprintf(
                'El Controller llama a %s::%s(). El acceso a datos va en un Action (Controller -> FormRequest -> Action -> Model).',
                $clase,
                $metodo,
            ))->identifier('gate.controllerQuery')->build(),
        ];
    }
}
