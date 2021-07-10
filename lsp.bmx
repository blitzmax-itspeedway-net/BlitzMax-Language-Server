SuperStrict

'   LANGUAGE SERVER EXTENSION FOR BLITZMAX NG
'   (c) Copyright Si Dunford, June 2021, All Right Reserved

Framework brl.standardio 
Import brl.collections      ' Used for Tokeniser
'Import brl.linkedlist
Import brl.map              ' Used as JSON dictionary
Import brl.reflection		' USed by JSON.transpose
Import brl.retro
Import brl.stringbuilder
Import brl.system
Import brl.threads
Import brl.threadpool

Import pub.freeprocess
'debugstop
'   INCLUDE APPLICATION COMPONENTS

'DebugStop

Include "bin/TObserver.bmx"
Include "bin/TMessageQueue.bmx"
Include "bin/TConfig.bmx"
Include "bin/TLogger.bmx"
'Include "bin/TTemplate.bmx"    ' Depreciated (Functionality moved into JSON)
Include "bin/json.bmx"

Include "bin/sandbox.bmx"

Include "handlers/handlers.bmx"

' RPC2.0 Error Messages
Const ERR_PARSE_ERROR:String =       "-32700"  'Invalid JSON was received by the server.
Const ERR_INVALID_REQUEST:String =   "-32600"  'The JSON sent is not a valid Request object.
Const ERR_METHOD_NOT_FOUND:String =  "-32601"  'The method does not exist / is not available.
Const ERR_INVALID_PARAMS:String =    "-32602"  'Invalid method parameter(s).
Const ERR_INTERNAL_ERROR:String =    "-32603"  'Internal JSON-RPC error.

' LSP Error Messages
Const ERR_SERVER_NOT_INITIALIZED:String = "-32002"
Const ERR_CONTENT_MODIFIED:String =       "-32801"
Const ERR_REQUEST_CANCELLED:String =      "-32800"

?win32
    Const EOL:String = "~n"
?Not win32
    Const EOL:String = "~r~n"
?

'   GLOBALS
AppTitle = "Language Server for BlitzMax NG"
Global DEBUGGER:Int = True

'DebugStop
'Global Version:String = "0.00 Pre-Alpha"
Local Logfile:TLogger = New TLogger()         ' Please use Observer
Global LSP:TLSP

'   DEBUG THE COMMAND LINE
Publish "log", "DEBG", "ARGS: ("+AppArgs.length+")"     '+(" ".join(AppArgs))
For Local n:Int=0 Until AppArgs.length
    Publish "log", "DEBG", n+") "+AppArgs[n]
Next
Publish "log", "DEBG", "CURRENTDIR: "+CurrentDir$()
Publish "log", "DEBG", "APPDIR:     "+AppDir

'   INCREMENT BUILD NUMBER

' @bmk include build.bmk
' @bmk incrementVersion build.bmx
Include "build.bmx"
Publish "log", "INFO", AppTitle
Publish "log", "INFO", "Version "+version+"."+build

'   MAIN APPLICATION

'DebugStop
Type TLSP Extends TObserver
    Global instance:TLSP

    Field exitcode:Int = 0

	Field initialized:Int = False   ' Set by "iniialized" message
    Field shutdown:Int = False      ' Set by "shutdown" message
    Field QuitMain:Int = True       ' Atomic State - Set by "exit" message

    Field queue:TMessageQueue = New TMessageQueue()

	' Create a document manager
	Field textDocument:TTextDocument	' Do not initialise here: Depends on lsp.

    ' Threads
    Field Receiver:TThread
    Field QuitReceiver:Int = True   ' Atomic State
    Field Sender:TThread
    Field QuitSender:Int = True     ' Atomic State
    Field ThreadPool:TThreadPoolExecutor
    Field ThreadPoolSize:Int
    Field sendMutex:TMutex = CreateMutex()
    
	' System
	Field capabilities:JSON = New JSON()	' Empty object
	Field handlers:TMap = New TMap
	
    Method run:Int() Abstract
    Method getRequest:String() Abstract     ' Waits for a message from client

    Method Close() ; End Method

	'V0.0
    Function ExitProcedure()
        'Publish( "debug", "Exit Procedure running" )
        Publish( "exitnow" )
        instance.Close()
        'Logfile.Close()
    End Function

	'V0.1
    ' Thread based message receiver
    Function ReceiverThread:Object( data:Object )
        Local lsp:TLSP = TLSP( data )
        Local quit:Int = False     ' Local loop state

        ' Read messages from Language Client
        Repeat

            Local node:JSON
                       
            ' Get inbound message from Language Client
            Local content:String = lsp.getRequest()

            ' Parse message into a JSON object
			Publish( "debug", "Parse starting" )
            Local J:JSON = JSON.Parse( content )
			Publish( "debug", "Parse finished" )
            ' Report an error to the Client using stdOut
            If Not J Or J.isInvalid()
				Local errtext:String
				If J.isInvalid()
					errtext = "ERROR("+J.errNum+") "+J.errText+" at {"+J.errLine+","+J.errpos+"}"
				Else
					errtext = "ERROR: Parse returned null"
				End If
                ' Send error message to LSP Client
				Publish( "debug", errtext )
                Publish( "send", Response_Error( ERR_PARSE_ERROR, errtext ) )
                Continue
            End If
			Publish( "debug", "Parse successful" )
			
            ' Debugging
            'Local debug:String = JSON.stringify(J)
            'logfile.write( "STRINGIFY:" )
            'logfile.write( "  "+debug )
   
            ' Check for a method
            node = J.find("method")
            If Not node 
                Publish( "send", Response_Error( ERR_METHOD_NOT_FOUND, "No method specified" ))
                Continue
            End If
            Local methd:String = node.tostring()
            'Publish( "log", "DEBG", "RPC METHOD: "+methd )
            If methd = "" 
                Publish( "send", Response_Error( ERR_INVALID_REQUEST, "Method cannot be empty" ))
                Continue
            End If
            ' Validation
            If Not LSP.initialized And methd<>"initialize"
                Publish( "send", Response_Error( ERR_SERVER_NOT_INITIALIZED, "Server is not initialized" ))
                Continue
            End If
                
            ' Transpose JNode into Blitzmax Object
            Local request:TMessage
            Try
                Local typestr:String = "TMethod_"+methd
                typestr = typestr.Replace( "/", "_" )
                typestr = typestr.Replace( "$", "dollar" ) ' Protocol Implementation Dependent
                'Publish( "log", "DEBG", "BMX METHOD: "+typestr )
                ' Transpose RPC
                request = TMessage( J.transpose( typestr ))
				' V0.2 - This is no longer a failure as we may have a handler
                'If Not request
                '    Publish( "log", "DEBG", "Transpose to '"+typestr+"' failed")
                '    Publish( "send", Response_Error( ERR_METHOD_NOT_FOUND, "Method is not available" ))
                '    Continue
                'Else
                '    ' Save JNode into message
                '    request.J = J
                'End If
				' V0.2, Save the original J node
				If request request.J = J
                If Not request Publish( "debug", "Transpose to '"+typestr+"' failed")
            Catch exception:String
                Publish( "send", Response_Error( ERR_INTERNAL_ERROR, exception ))
            End Try

			' V0.2
			' If Transpose fails, then all is not lost
			If Not request
				Publish( "debug", "Creating V0.2 message object")
				request = New TMessage( methd, J )
			End If
    
            ' A Request is pushed to the task queue
            ' A Notification is executed now
            If request.contains( "id" )
                ' This is a request, add to queue
                Publish( "debug", "Pushing request to queue")
                Publish( "pushtask", request )
                'lsp.queue.pushTaskQueue( request )
                Continue
            Else
                ' This is a Notification, execute it now and throw away any response
                Try
                    Publish( "debug", "Notification "+methd+" starting" )
                    request.run()
                    Publish( "debug", "Notification "+methd+" completed" )
                Catch exception:String
                    Publish( "send", Response_Error( ERR_INTERNAL_ERROR, exception ))    
                End Try
            End If
        Until CompareAndSwap( lsp.QuitReceiver, quit, True )
        'Publish( "debug", "ReceiverThread - Exit" )
    End Function

	'V0.1
    ' Thread based message sender
    Function SenderThread:Object( data:Object )
        Local lsp:TLSP = TLSP( data )
        Local quit:Int = False          ' Always got to know when to quit!
        
        'DebugLog( "SenderThread()" )
        Repeat
            Try
                'Publish( "debug", "Sender thread going to sleep")
                WaitSemaphore( lsp.queue.sendcounter )
                'Publish( "debug", "SenderThread is awake" )
                ' Create a Response from message
                Local content:String = lsp.queue.popSendQueue()
                Publish( "log", "DEBG", "Sending '"+content+"'" )
                If content<>""  ' Only returns "" when thread exiting
                    Local response:String = "Content-Length: "+Len(content)+EOL
                    response :+ EOL
                    response :+ content
                    ' Log the response
                    Publish( "log", "DEBG", "Sending:~n"+response )
                    ' Send to client
                    LockMutex( lsp.sendMutex )
                    StandardIOStream.WriteString( response )
                    StandardIOStream.Flush()
                    UnlockMutex( lsp.sendMutex )
                    'Publish( "debug", "Content sent" )
                End If
            Catch Exception:String 
                'DebugLog( Exception )
                Publish( "log", "CRIT", Exception )
            End Try
        Until CompareAndSwap( lsp.QuitSender, quit, True )
        Publish( "debug", "SenderThread - Exit" )
    End Function  

	'V0.2
	' Add a Capability
	'Method addCapability( capability:String )
	'	capabilities :+ [capability]
	'End Method	

	'V0.2
	' Retrieve all registered capabilities
	'Method getCapabilities:String[][]()
	'	Local result:String[][]
	'	For Local capability:String = EachIn capabilities
	'		result :+ [[capability,"true"]]
	'	Next
	'	Return result
	'End Method

	'V0.2
	' Add Message Handler
	Method addHandler( handler:TMessageHandler, events:String[] )
		For Local event:String = EachIn events
			handlers.insert( event, handler )
		Next
	End Method

	'V0.2
	' Get a Message Handler
	Method getMessageHandler:TMessageHandler( methd:String )
		Return TMessageHandler( handlers.valueForkey( methd ) )
	End Method
	
End Type

' RESERVED FOR FUTURE EXPANSION
Type TLSP_TCP Extends TLSP
    Method Run:Int()
		textDocument = New TTextDocument
	End Method
    Method getRequest:String() ; End Method
End Type

' StdIO based LSP
Type TLSP_Stdio Extends TLSP
	Field StdIn:TStream

    Method New( threads:Int = 4 )
        Publish( "info", "LSP for BlitzMax NG" )
        Publish( "info", "V"+Version+"."+build )
        'Log.write( "Initialised")
        ' Set up instance and exit function
        instance = Self
        OnEnd( TLSP.ExitProcedure )
        ' Debugstop
        ThreadPoolSize = threads
		ThreadPool = TThreadPoolExecutor.newFixedThreadPool( ThreadPoolSize )
        '
        ' Observations
        'Subscribe( [""] )
    End Method

    Method run:Int()
		textDocument = New TTextDocument

        Local quit:Int = False     ' Local loop state

        ' Open StandardIn
        StdIn = ReadStream( StandardIOStream )
        If Not StdIn
            Publish( "log", "CRIT", "Failed to open StdIN" )
            Return 1
        End If

        ' Start threads
        Receiver = CreateThread( ReceiverThread, Self )
        Sender = CreateThread( SenderThread, Self )
        'ThreadPool = TThreadPoolExecutor.newFixedThreadPool( ThreadPoolSize )
'DebugStop
        ' Start Message Loop
        Repeat
            ' Fill thread pool
            While ThreadPool.threadsWorking < ThreadPool.maxThreads            
                ' Get next task from queue
				Local task:TMessage = queue.getNextTask()
				If Not task Exit
				' Process the event handler
				ThreadPool.execute( New TRunnableTask( task, Self ) )
            Wend
            Delay(100)
        'Until endprocess
        Until CompareAndSwap( lsp.QuitMain, quit, True )
        Publish( "debug", "Mainloop - Exit" )
        
        ' Clean up and exit gracefully
        AtomicSwap( QuitReceiver, False )   ' Inform thread it must exit
        DetachThread( Receiver )
        Publish( "debug", "Receiver thread closed" )

        AtomicSwap( QuitSender, False )     ' Inform thread it must exit
        'PostSemaphore( queue.sendCounter )  ' Wake the thread from it's slumber
        DetachThread( Sender )
        Publish( "debug", "Sender thread closed" )

        ThreadPool.shutdown()
        Publish( "debug", "Worker thread pool closed" )

        Return exitcode
    End Method
    
    ' Observations
    Method Notify( event:String, data:Object, extra:Object )
    '    Select event
    '    Case "receive"
    '        MessageReceiver( string( data ) )
    '    case "send"
    '        MessageSender( string( data ) )
    '    End Select
    End Method

    ' Read messages from the client
    Method getRequest:String()
        Local quit:Int = False     ' Local loop state
        Local line:String   ', char:String
        Local content:String
        Local contentlength:Int
		Local contenttype:String = "utf-8"

        'Publish( "log", "DEBG", "STDIO.GetRequest()")
        ' Read messages from StdIN
        Repeat
            Try
                line = stdIn.ReadLine()
                If line.startswith("Content-Length:")
                    contentlength = Int( line[15..] )
                    'Publish( "log", "DEBG", "Content-Length:"+contentlength)
                ElseIf line.startswith("Content-Type:")
                    contenttype = Int( line[13..] )
                    ' Backward compatibility, utf8 is no longer supported
                    If contenttype = "utf8" contenttype = "utf-8"
                    'Publish( "log", "DEBG", "Content-Type:"+contenttype)
                ElseIf line=""
                    'Publish( "log", "DEBG", "WAITING FOR CONTENT...")
                    content = stdIN.ReadString$( contentlength )
                    'Publish( "log", "DEBG", "Received "+contentlength+" bytes:~n"+content )
                    Publish( "log", "DEBG", "Received "+contentlength+" bytes" )
                    Return content
                Else
                    Publish( "log", "DEBG", "Skipping: "+line )
                End If
            Catch Exception:String
                Publish( "critical", Exception )
            End Try
        'Until endprocess
        Until CompareAndSwap( lsp.QuitMain, quit, True )
    End Method

End Type

Function Response_Error:String( code:String, message:String, id:String="null" )
    Publish( "log", "ERRR", message )
    Local response:JSON = New JSON()
    response.set( "id", id )
    response.set( "jsonrpc", "2.0" )
    response.set( "error", [["code",code],["message","~q"+message+"~q"]] )
    Return response.stringify()
End Function

'   Worker Thread
Type TRunnableTask Extends TRunnable
    Field message:TMessage
    Field lsp:TLSP
    Method New( handler:TMessage, lsp:TLSP )
        Self.message = handler
        Self.lsp = lsp
    End Method
    Method run()
		Local response:String = message.run()
		'V0.2, default to error if nothign returned from handler
		If response="" response = Response_Error( ERR_METHOD_NOT_FOUND, "Method is not available", message.id )
		' Send the response to the client
		Publish( "sendmessage", response )
		'lsp.queue.pushSendQueue( response )
		' Close the request as complete
		message.state = STATE_COMPLETE
    End Method
End Type

'   Run the Application
Publish( "log", "DEBG", "Starting LSP..." )

'DebugStop

Try
    LSP = New TLSP_Stdio( Int(CONFIG["threadpool"]) )
    exit_( LSP.run() )
    'Publish( "debug", "Exit Gracefully" )
Catch exception:String
    Publish( "log", "CRIT", exception )
End Try
