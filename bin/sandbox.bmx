'   SANDBOX
'   This contains the code I am working on

Type TResponse

rem    interface ResponseMessage extends Message {
        /**
         * The request id.
         */
        id: integer | string | null;
    
        /**
         * The result of a request. This member is REQUIRED on success.
         * This member MUST NOT exist if there was an error invoking the method.
         */
        result?: string | number | boolean | object | null;
    
        /**
         * The error object in case a request fails.
         */
        error?: ResponseError;
    }
end rem
End Type