<?php

class UserExistsHooks {
    public static function onParserFirstCallInit( Parser $parser ) {
        $parser->setFunctionHook( 'userexists', [ self::class, 'renderUserExists' ] );
        return true;
    }

    public static function renderUserExists( Parser $parser, $username = '' ) {
        $user = User::newFromName( $username );
        if ( !$user || !$user->getId() ) {
            return 'no';
        }
        return 'yes';
    }
}
