
'	BlitzMax Parser
'	(c) Copyright Si Dunford, July 2021, All Rights Reserved

Include "TParser.bmx"

'	A LANGUAGE SYNTAX IS CURRENTLY UNAVAILABLE
'	THIS IS THEREFORE HARDCODED AT THE MOMENT
'	IT WILL BE RE-WRITTEN WHEN SYNTAX IS DONE

Type TBlitzMaxParser Extends TParser

	Field strictmode:Int = 0
	
	' The story starts, as they say, with a beginning...
	Method parse:AST()
		
		Rem 	ABNF
				Program = [ Application | Module ]
				Application = [Strictmode] [Framework] [*Import] [*Include] Block
				Module = [Strictmode] ModuleDef [*Import] [*Include] Block
		End Rem
DebugStop
		'	OPTIONAL STRICTMODE
		'	StrictMode = "superstrict" / "strict" EOL
		If lexer.peek( ["superstrict","strict"] )
			token_strictmode( lexer.getnext() )
		End If
		
		'	OPTIONAL FRAMEWORK
		'	Framework = "framework" ModuleIdentifier EOL
		If lexer.peek( ["framework"] )
			Print "FRAMEWORK"
			token_framework( lexer.getnext() )
		End If
		
		'	OPTIONAL IMPORTS
		'	OPTIONAL INCLUDES
		'	OPTIONAL EXTERN
		
		'	APPLICATION CODE BODY
		Parse_Body( ["local","global","function","type","print"] )

		If lexer.isAtEnd() Return Null 'Completed successfully
		
		' Symbols exist past end of file!
		Local sym:TSymbol = lexer.peek()
		ThrowException( "Unexpected Symbol", sym.line, sym.pos )

	End Method

	Private
	
	'	DYNAMIC METHODS
	'	CALLED BY REFLECTOR

	' Field = "field" VarDecl *[ "," VarDecl ]
	Method token_field( token:TSymbol )
		Parse_VarDeclarations( "field", token )
	End Method
	
	' Framework = "framework" ModuleIdentifier EOL
	' ModuleIdentifier = Name DOT Name
	' Name = ALPHA *(ALPHA / DIGIT / UNDERSCORE )
	Method token_framework( token:TSymbol )
		Local moduleIdentifier:String = Parse_ModuleIdentifier()
		' Add to symbol table
		symbolTable.add( token, "global", moduleIdentifier ) 
	End Method

	' Global = "global" VarDecl *[ "," VarDecl ]
	Method token_global( token:TSymbol )
		Parse_VarDeclarations( "global", token )
	End Method

	' Local = "local" VarDecl *[ "," VarDecl ]
	Method token_local( token:TSymbol )
DebugStop
		Parse_VarDeclarations( "local", token )
Print "LOCAL DONE"
	End Method
	
	' StrictMode = "superstrict" / "strict" EOL
	Method token_strictmode( token:TSymbol )
		Select token.class
		Case "strict"		;	strictmode = 1
		Case "superstrict"	;	strictmode = 2
		End Select
		'lexer.expect( "EOL" )
	End Method
	
	'	STATIC METHODS
	'	CALLED DIRECTLY
	
	' ApplicationBody = Local / Global / Function / Struct / Type / BlockBody
	Method Parse_Body:String( expected:String[] )
		Local sym:TSymbol
		Local found:TSymbol
		Repeat
			sym = lexer.peek()
			DebugStop
			If sym.class="EOF" 
				lexer.getNext()
				Exit
			End If
			If sym.class="EOL" Or sym.class="comment"
				lexer.getNext()
				Continue
			End If
			found = Null
			For Local expect:String = EachIn expected
				If expect=sym.class 
					found = sym
					Exit
				End If
			Next
			'
			If found  ' Expected Symbol
				' REFLECT IS FAULTY - DO NOT GO THERE
				'reflect( lexer.getNext() )
				' 
				Local symbol:TSymbol = lexer.getNext()
				Select symbol.class
				Case "field"		;	Parse_VarDeclarations( "field", token )
				Case "global"		;	Parse_VarDeclarations( "global", token )
				Case "local"		;	Parse_VarDeclarations( "local", token )
				Default
					ThrowException( "Unhandled Symbol '"+sym.value+"'", sym.line, sym.pos )
				End Select
			Else
				' Unexpected symbol...
				ThrowException( "Unexpected Symbol '"+sym.value+"'", sym.line, sym.pos )
			End If
		Forever
	End Method
	
	' ModuleIdentifier = Name DOT Name
	Method Parse_ModuleIdentifier:String()
		Local collection:TSymbol = lexer.Expect( "alpha" )
		lexer.Expect( "symbol", "." )
		Local name:TSymbol = lexer.Expect( "alpha" )
		Return collection.value + "." + name.value
	End Method
	
	' VarDeclarations = VarDecl *[ "," VarDecl ]
	Method Parse_VarDeclarations( scope:String, symbol:TSymbol )
		Local sym:TSymbol
DebugStop
'Print "Did I get here?"
		Repeat
			Parse_VarDecl( symbol, scope )
			sym = lexer.peek()
		Until sym.class = "EOF" Or sym.class<>"comma"		
	End Method

	' VarDecl = Name ":" VarType [ "=" Expression ]
	Method Parse_VarDecl( definition:TSymbol, scope:String )
DebugStop
		' Parse Variable defintion
		Local name:TSymbol = lexer.Expect( "alpha" )
		lexer.expect( "colon" )
		Local varType:String = Parse_VarType()
		' Parse optional declaration
		If lexer.peek( "equals" )
			Local sym:TSymbol
			' Throw away the expression. NOT IMPLEMENTED YET
			Repeat
				sym = lexer.getNext()
				'Print sym.class
			Until sym.in(["EOL","EOF","comma","comment"])
		End If
		' Create Defintion Table
		symbolTable.add( definition, scope, name.value, vartype )
	End Method

	' VarType = "byte" / "int" / "string" / "double" / "float" / "size_t"
	Method Parse_VarType:String()
		Local sym:TSymbol = lexer.getNext()
		Return sym.value
	End Method
	
End Type