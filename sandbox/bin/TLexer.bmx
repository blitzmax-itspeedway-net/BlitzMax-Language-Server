
'	Generic Lexer
'	(c) Copyright Si Dunford, July 2021, All Rights Reserved

Type TLexer

	Private
	
	Const SYM_WHITESPACE:String = " ~t~n~r"
	Const SYM_SPACE:String = " "
    Const SYM_NUMBER:String = "0123456789"
    Const SYM_LOWER:String = "abcdefghijklmnopqrstuvwxyz"
    Const SYM_UPPER:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    Const SYM_ALPHA:String = SYM_LOWER+SYM_UPPER
	Const SYM_7BIT:String = SYM_SPACE+"!#$%&'()*+,-./"+SYM_NUMBER+":;<=>?@"+SYM_UPPER+"[]^_`"+SYM_LOWER+"{|}"
		
	Field source:String, reserved:String
	Field linenum:Int, linepos:Int	' Source 
	Field cursor:Int				' Lexer (Char cursor)
	Field sympos:TLink				' Current symbol cursor
	
	Field symbols:TList = New TList()
	Field tokens:TMap = New TMap()	' List of known tokens. Key is symbol, Value is class
	
	' Language specific elements
	Field include_comments:Int = False
	Field linecomment_symbol:String = "'"
	Field valid_symbols:String = ""
	Field compound_symbols:String = ""	' Must be separated by a non-symbol
	
	Public
	
	Method New( source:String, reserved:String="" )
		Self.source = source
		Self.reserved = reserved
		cursor = 0
		linenum = 1 ; linepos = 0
		symbols.clear()
	End Method 

	Method defineToken( symbol:String, class:String )
		tokens.insert( symbol, class )
	End Method

	Method run()
		Try
			tokenise()
		Catch Exception:String
			Print "## EXCEPTION"
			Print Exception
		End Try
	End Method

	' Produce a symbol table to help debugging
	Method reveal:String()
		Local result:String
		For Local symbol:TSymbol = EachIn symbols
			result :+ symbol.reveal()+"~n"
		Next
		Return result
	End Method

    ' Gets the next Symbol from the list
    Method getNext:TSymbol()	' ignorelist:String="" )
        'If sympos=Null Or symbols.isempty() Return New TSymbol( "EOF","", linenum, linepos)
        If sympos=Null Return New TSymbol( "EOF","", linenum, linepos)
		Local sym:Object = sympos.value
		sympos = sympos.nextlink
        Return TSymbol(sym)
    End Method

    ' Pops the first symbol from the stack
    'Method Pop:TSymbol()	' ignorelist:String="" )
    '    If symbols.isempty() Return New TSymbol( "EOF","", linenum, linepos)
    '    Return symbols.dequeue()
    'End Method

    ' Peeks the top of the symbol Stack
    Method Peek:TSymbol( expectedclass:String="" )
        'If symbols.isempty() Return New TSymbol( "EOF","", linenum, linepos)
        If sympos=Null Return New TSymbol( "EOF","", linenum, linepos)
		If expectedclass="" Return TSymbol( sympos.value )
		Local peek:TSymbol = TSymbol( sympos.value )
		If peek.class=expectedclass Return peek
        Return Null
    End Method

    ' Peeks the top of the symbol Stack
    Method Peek:TSymbol( expectedclass:String[]=[] )
        'If symbols.isempty() Return New TSymbol( "EOF","", linenum, linepos)
        If sympos=Null Return New TSymbol( "EOF","", linenum, linepos)
		If expectedclass=[] Return TSymbol( sympos.value )
		Local peek:TSymbol = TSymbol( sympos.value )
		For Local expected:String = EachIn expectedclass
			If peek.class=expected Return peek
		next
        Return Null
    End Method

    ' Matches the next symbol otherwise throws an error
    Method Expect( expectedclass:String, expectedvalue:String="" )
		Local sym:TSymbol = TSymbol( sympos.value )
		If sym.class = expectedclass
			If expectedvalue = "" Or sym.value = expectedvalue Return
		End If
		Throw( "Unexpected symbol" )
    End Method

    ' Matches the given symbol and throws it away (Useful for comments)
    Method skip:String( expectedclass:String )
		Local sym:TSymbol = TSymbol( sympos.value )
		Local skipped:String
		While sym.class = expectedclass
			skipped :+ sym.value
			sympos = sympos.nextlink
			sym = TSymbol( sympos.value )
		Wend
		Return skipped
    End Method

	Private
	
	Method tokenise()
'DebugStop
		Local symbol:TSymbol	' = nextSymbol()
		Repeat
'DebugStop
			symbol = nextSymbol()
			If symbol.class<>"comment" Or include_comments
				symbols.addlast( symbol )
			End If
		Until symbol.class = "EOF"
		' Set the symbol cursor to the first element
		sympos = symbols.firstLink()
	End Method
	
	Method nextSymbol:TSymbol()
'DebugStop
		'Local name:String
		'Local symbol:TSymbol
		' Save the symbol position
		Local line:Int = linenum
		Local pos:Int = linepos
		' Identify the symbol
		Local char:String = PeekChar()
		If char=""
			Return New TSymbol( "EOF", "", line, pos )
		ElseIf char = linecomment_symbol						' Line Comment
			Return New TSymbol( "comment", ExtractLineComment(), line, pos )
		ElseIf Instr( valid_symbols, char, 1 )               ' Single character symbol
			PopChar()   ' Move to next character
			' Check for Compound symbols
			If Instr( compound_symbols, char+peekChar() )
				Return LexSymbol( char+PopChar(), line, pos )
			Else
				Return LexSymbol( char, line, pos )
			End If
		ElseIf char="~q"                            ' Quote indicates a string
			Return LexQuotedString( ExtractString(), line, pos )
		ElseIf Instr( SYM_NUMBER+"-", char )     	' Number
			Return LexNumber( ExtractNumber(), line, pos )
		ElseIf Instr( SYM_ALPHA, char )             ' Alphanumeric Identifier
			Return LexAlpha( ExtractIdent(), line, pos )
		Else
			PopChar()   ' Throw it away!
			Return LexInvalid( char, line, pos )
		End If		
	End Method
	
    ' Skips leading whitespace and returns next character
    Method PeekChar:String( IgnoredSymbols:String = SYM_WHITESPACE )
'DebugStop
        Local char:String
        Repeat
            If cursor>=source.length Return ""
            char = source[cursor..cursor+1]
            Select char
            Case "~r"   ' CR
				cursor :+1
            Case "~n"   ' LF
                linenum :+1
                linepos = 1
				cursor :+1
            Case " ","~t"
                linepos:+1
				cursor :+1
			Case "\"	' ESCAPE CHARACTER
				char = source[cursor..(cursor+1)]
				If char="\u"	'HEX DIGIT
					char = source[cursor..(cursor+5)]					
					cursor :+ 6
				Else
					cursor :+ 2
				End If
            End Select
        Until Not Instr( IgnoredSymbols, char )
        Return char
    End Method

	' Pops next character moving the cursor forward
    Method PopChar:String( IgnoredSymbols:String = SYM_WHITESPACE )
'DebugStop
        Local char:String
		'Local IgnoredSymbols:String = ""
		'
		'If ignoreWhitespace IgnoredSymbols = whitespace
		
        Repeat
            If source.length = 0 Return ""
            char = source[cursor..cursor+1]
            Select char
            Case "~r"   ' CR
                cursor :+ 1
            Case "~n"   ' LF
                linenum :+ 1
                linepos = 1
                cursor :+ 1
			Case "\"	' ESCAPE CHARACTER
				char = source[cursor..cursor+1]
				If char="\u"	'HEX DIGIT
					char = source[cursor..cursor+5]			
					cursor :+ 6
				Else
					cursor :+ 2
				End If
            Default
                linepos :+ 1
                cursor :+ 1
            End Select
        Until Not Instr( IgnoredSymbols, char )
        Return char
    End Method

    Method ExtractIdent:String()
'DebugStop
        Local text:String
        Local char:String = peekChar()
        While Instr( SYM_ALPHA, char ) And char<>""
            text :+ popChar()
            char = PeekChar("")
        Wend
        Return text
    End Method

	Method ExtractLineComment:String()
'DebugStop
		' Line comments extend until CRLF
        Local text:String
        Local char:String
		popChar()   ' Throw away leading comment starting character 
        Repeat
            char = PopChar( "~r" )		' Pop char but do not ignore whitespace
			' We don't need to actually return them... do we?
			text :+ char
        Until char="~n" Or char=""
		'If text.endswith( "~n" ) text = text[..(text.length-1)]
		text = Trim( text )
        Return text
	End Method
	
    Method ExtractNumber:String()
'DebugStop
        Local text:String
        Local char:String = peekChar()
		' Leading "-" (Negative number)
		If char="-"	
			text :+ popChar()
			char = peekChar()
		End If
		' Number
        While Instr( SYM_NUMBER, char ) And char<>""
            text :+ popChar()
            char = PeekChar()
        Wend
		' Decimal
		If char="."
			text :+ popChar()
            char = PeekChar()
			While Instr( SYM_NUMBER, char ) And char<>""
				text :+ popChar()
				char = PeekChar()
			Wend			
		End If
        Return text
    End Method

    Method ExtractString:String()
'DebugStop
        Local text:String = popChar()   ' This is the leading Quote
        Local char:String 
        Repeat
            char = PopChar( "" )		' Pop char, but do not ignore whitespace
			Select char.length
			Case 1
				text :+ char
			Case 2	' ESCAPE CHARACTER?
				Select char
				Case "\~q","\\","\/"
					text :+ char[1..]
				Case "\n","\r","\t"
					text :+ "~~"+char[1..]
				Case "\b"
					text :+ Chr(08)
				Case "\f"
					text :+ Chr(12)
				End Select
			Case 6	' HEXCODE
				Local hexcode:String = "$"+char[2..]
				Print char + " == " + hexcode
				text :+ Chr( Int( hexcode ) )
			End Select
        Until char="~q" Or char=""
        Return text
    End Method
	
	' EXTENDABLE LEXER METHODS
	
	Method LexAlpha:TSymbol( text:String, line:Int, pos:Int )
		Local symbol:String = String( tokens.valueforkey( Lower(text) ))
		If symbol = ""
			Return New TSymbol( "alpha", text, line, pos )
		Else
			Return New TSymbol( symbol, text, line, pos )
		End If
	End Method

	Method LexInvalid:TSymbol( text:String, line:Int, pos:Int )
		Return New TSymbol( "invalid", text, line, pos )
	End Method

	Method LexNumber:TSymbol( text:String, line:Int, pos:Int )
		Return New TSymbol( "number", text, line, pos )
	End Method
	
	Method LexQuotedString:TSymbol( text:String, line:Int, pos:Int )
		Return New TSymbol( "string", text, line, pos )
	End Method

	Method LexSymbol:TSymbol( text:String, line:Int, pos:Int )
		Return New TSymbol( "symbol", text, line, pos )
	End Method
	
End Type