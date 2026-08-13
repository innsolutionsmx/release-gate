<?php

namespace Gate\PHPStan\Rules;

use PhpParser\Node;
use PhpParser\Node\Expr\MethodCall;
use PHPStan\Analyser\Scope;
use PHPStan\Rules\Rule;
use PHPStan\Rules\RuleErrorBuilder;

/**
 * Prohíbe escribir en la base desde un Controller sobre un Model ya resuelto
 * (típicamente uno que llegó por route model binding): $user->save(),
 * $user->delete(), $post->update([...]).
 *
 * Las LECTURAS sobre el model bindeado (por ejemplo $user->load('roles') para
 * la vista) quedan permitidas a propósito: son idiomáticas y no son el patrón
 * de erosión que buscamos. Lo que no puede pasar es que la escritura viva en
 * el Controller en vez de en un Action.
 *
 * @implements Rule<MethodCall>
 */
class NoModelPersistCallInControllerRule implements Rule
{
    use ControllerScope;

    /** Métodos que escriben en la base. */
    private const ESCRITURA = [
        'save', 'saveOrFail', 'delete', 'forceDelete', 'restore', 'update',
        'updateOrFail', 'push', 'increment', 'decrement', 'touch',
        'associate', 'dissociate', 'forceFill',
    ];

    public function getNodeType(): string
    {
        return MethodCall::class;
    }

    public function processNode(Node $node, Scope $scope): array
    {
        if (! $this->enControlador($scope)) {
            return [];
        }

        if (! $node->name instanceof Node\Identifier) {
            return [];
        }

        $metodo = $node->name->toString();

        if (! in_array($metodo, self::ESCRITURA, true)) {
            return [];
        }

        if (! $this->esModelo($scope->getType($node->var))) {
            return [];
        }

        return [
            RuleErrorBuilder::message(sprintf(
                'El Controller escribe en la base con ->%s(). La persistencia va en un Action (Controller -> FormRequest -> Action -> Model).',
                $metodo,
            ))->identifier('gate.controllerPersist')->build(),
        ];
    }
}
