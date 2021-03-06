@ECHO OFF
@rem **************************************************************************
@rem discoverDomain.cmd
@rem
@rem Copyright (c) 2017, 2020, Oracle Corporation and/or its affiliates.  All rights reserved.
@rem Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
@rem
@rem     NAME
@rem       discoverDomain.cmd - WLS Deploy tool to discover a domain.
@rem
@rem     DESCRIPTION
@rem       This script discovers the model of an existing domain and gathers
@rem       the binaries needed to recreate the domain elsewhere with all of
@rem       its applications and resources configured.
@rem
@rem
@rem This script uses the following command-line arguments directly, the rest
@rem of the arguments are passed down to the underlying python program:
@rem
@rem     - -oracle_home        The directory of the existing Oracle Home to use.
@rem                           This directory must exist and it is the caller^'s
@rem                           responsibility to verify that it does. This
@rem                           argument is required.
@rem
@rem     - -domain_home        The existing domain home to discover. This argument
@rem                           is required.
@rem
@rem     - -domain_type        The type of domain to discover. If this is set to
@rem                           other than WLS, it will use the black list components
@rem                           section in the corresponding typedef file to remove
@rem                           MBeans from the model that were added by a template.
@rem                           This argument is optional.  If not specified, it
@rem                           defaults to WLS.
@rem
@rem     - -model_file         The name of a file where to write the discovered domain model.
@rem                           This argument is required.
@rem
@rem     - -archive_file       The name of a file where to archive the collected files from the
@rem                           discovered domain. This argument is required. However, if no
@rem                           files are collected from the domain, the tool will not create the file
@rem
@rem     - -variable_file      The name of a variable file where the variable injector will write
@rem                           properties specified for the tool run. By default, if this file is
@rem                           included on the command line, all credentials in the model will
@rem                           be tokenized, with the variable name written to this file. This
@rem                           argument is optional. If not specified, and directives for the
@rem                           variable injector exist, the default file name will be created.
@rem
@rem     - -admin_user         User name for the admin Server to discover the specified domain in WLST
@rem                           online mode. Note that the server must be running in the same location
@rem                           as the discoverDomain so that any files can be collected
@rem                           into the archive file. The user will be prompted for the admin password
@rem                           from STDIN. This argument is optional. If not specified, the
@rem                           discover tool will run in WLST offline mode.
@rem
@rem     - -admin_url          URL of the admin server for discovery of the domain in WLST online mode.
@rem                           This argument is required if -admin_user is specified.
@rem
@rem     - -wlst_path          The path to the Oracle Home product directory under
@rem                           which to find the wlst.cmd script.  This is only
@rem                           needed for pre-12.2.1 upper stack products like SOA.
@rem
@rem                           For example, for SOA 12.1.3, -wlst_path should be
@rem                           specified as %ORACLE_HOME%\soa
@rem
@rem     - -java_home          The path to the Java Home directory used for the
@rem                           Oracle Home. This overrides the JAVA_HOME environment variable
@rem                           when discovering attributes with a java home. Any attribute with this
@rem                           value will be replaced with a java home global token in the model.
@rem
@rem This script uses the following variables:
@rem
@rem JAVA_HOME            - The location of the JDK to use.  The caller must set
@rem                        this variable to a valid Java 7 (or later) JDK.
@rem
@rem WLSDEPLOY_HOME        - The location of the WLS Deploy installation.
@rem                         If the caller sets this, the callers location will be
@rem                         honored provided it is an existing directory.
@rem                         Otherwise, the location will be calculated from the
@rem                         location of this script.
@rem
@rem WLSDEPLOY_PROPERTIES  - Extra system properties to pass to WLST.  The caller
@rem                         can use this environment variable to add additional
@rem                         system properties to the WLST environment.
@rem

SETLOCAL

SET WLSDEPLOY_PROGRAM_NAME=discoverDomain

SET SCRIPT_NAME=%~nx0
SET SCRIPT_PATH=%~dp0
FOR %%i IN ("%SCRIPT_PATH%") DO SET SCRIPT_PATH=%%~fsi
IF %SCRIPT_PATH:~-1%==\ SET SCRIPT_PATH=%SCRIPT_PATH:~0,-1%

IF NOT DEFINED WLSDEPLOY_HOME (
  SET WLSDEPLOY_HOME=%SCRIPT_PATH%\..
) ELSE (
  IF NOT EXIST "%WLSDEPLOY_HOME%" (
    ECHO Specified WLSDEPLOY_HOME of "%WLSDEPLOY_HOME%" does not exist >&2
    SET RETURN_CODE=2
    GOTO exit_script
  )
)
FOR %%i IN ("%WLSDEPLOY_HOME%") DO SET WLSDEPLOY_HOME=%%~fsi
IF %WLSDEPLOY_HOME:~-1%==\ SET WLSDEPLOY_HOME=%WLSDEPLOY_HOME:~0,-1%

@rem
@rem Make sure that the JAVA_HOME environment variable is set to point to a
@rem JDK 7 or higher JVM (and that it isn't OpenJDK).
@rem
IF NOT DEFINED JAVA_HOME (
  ECHO Please set the JAVA_HOME environment variable to point to a Java 7 or later installation >&2
  SET RETURN_CODE=2
  GOTO exit_script
) ELSE (
  IF NOT EXIST "%JAVA_HOME%" (
    ECHO Your JAVA_HOME environment variable to points to a non-existent directory: %JAVA_HOME% >&2
    SET RETURN_CODE=2
    GOTO exit_script
  )
)
FOR %%i IN ("%JAVA_HOME%") DO SET JAVA_HOME=%%~fsi
IF %JAVA_HOME:~-1%==\ SET JAVA_HOME=%JAVA_HOME:~0,-1%

IF EXIST %JAVA_HOME%\bin\java.exe (
  FOR %%i IN ("%JAVA_HOME%\bin\java.exe") DO SET JAVA_EXE=%%~fsi
) ELSE (
  ECHO Java executable does not exist at %JAVA_HOME%\bin\java.exe does not exist >&2
  SET RETURN_CODE=2
  GOTO exit_script
)

FOR /F %%i IN ('%JAVA_EXE% -version 2^>^&1') DO (
  IF "%%i" == "OpenJDK" (
    ECHO JAVA_HOME %JAVA_HOME% contains OpenJDK^, which is not supported >&2
    SET RETURN_CODE=2
    GOTO exit_script
  )
)

FOR /F tokens^=2-5^ delims^=.-_^" %%j IN ('%JAVA_EXE% -fullversion 2^>^&1') DO (
  SET "JVM_FULL_VERSION=%%j.%%k.%%l_%%m"
  SET "JVM_VERSION_PART_ONE=%%j"
  SET "JVM_VERSION_PART_TWO=%%k"
)

SET JVM_SUPPORTED=1
IF %JVM_VERSION_PART_ONE% LEQ 1 (
    IF %JVM_VERSION_PART_TWO% LSS 7 (
		SET JVM_SUPPORTED=0
    )
)
IF %JVM_SUPPORTED% NEQ 1 (
  ECHO You are using an unsupported JDK version %JVM_FULL_VERSION% >&2
  SET RETURN_CODE=2
  GOTO exit_script
) ELSE (
  ECHO JDK version is %JVM_FULL_VERSION%, setting JAVA_VENDOR to Sun...
  SET JAVA_VENDOR=Sun
)
@rem
@rem Check to see if no args were given and print the usage message
@rem
IF "%~1" == "" (
  SET RETURN_CODE=0
  GOTO usage
)

@rem
@rem Find the args required to determine the WLST script to run
@rem

SET ORACLE_HOME=
SET DOMAIN_TYPE=
SET WLST_PATH_DIR=
:arg_loop
IF "%1" == "-help" (
  SET RETURN_CODE=0
  GOTO usage
)
IF "%1" == "-oracle_home" (
  SET ORACLE_HOME=%2
  SHIFT
  GOTO arg_continue
)
IF "%1" == "-domain_type" (
  SET DOMAIN_TYPE=%2
  SHIFT
  GOTO arg_continue
)
IF "%1" == "-wlst_path" (
  SET WLST_PATH_DIR=%2
  SHIFT
  GOTO arg_continue
)
@REM If none of the above, a general argument so skip collecting it
:arg_continue
SHIFT
IF NOT "%~1" == "" (
  GOTO arg_loop
)

SET SCRIPT_ARGS=%*
@rem Default domain type if not specified
IF "%DOMAIN_TYPE%"=="" (
    SET SCRIPT_ARGS=%SCRIPT_ARGS% -domain_type WLS
)

@rem
@rem Check for values of required arguments for this script to continue.
@rem The underlying WLST script has other required arguments.
@rem
IF "%ORACLE_HOME%" == "" (
  ECHO Required argument -oracle_home not provided >&2
  SET RETURN_CODE=99
  GOTO usage
)

@rem
@rem If the WLST_PATH_DIR is specified, validate that it contains the wlst.cmd script
@rem
IF DEFINED WLST_PATH_DIR (
  FOR %%i IN ("%WLST_PATH_DIR%") DO SET WLST_PATH_DIR=%%~fsi
  IF NOT EXIST "%WLST_PATH_DIR%" (
    ECHO Specified -wlst_path directory does not exist: %WLST_PATH_DIR% >&2
    SET RETURN_CODE=98
    GOTO exit_script
  )
  set "WLST=%WLST_PATH_DIR%\common\bin\wlst.cmd"
  IF NOT EXIST "%WLST%" (
    ECHO WLST executable %WLST% not found under -wlst_path directory %WLST_PATH_DIR% >&2
    SET RETURN_CODE=98
    GOTO exit_script
  )
  SET CLASSPATH=%WLSDEPLOY_HOME%\lib\weblogic-deploy-core.jar
  SET WLST_EXT_CLASSPATH=%WLSDEPLOY_HOME%\lib\weblogic-deploy-core.jar
  GOTO found_wlst
)

@rem
@rem Find the location for wlst.cmd
@rem
SET WLST=

IF EXIST "%ORACLE_HOME%\oracle_common\common\bin\wlst.cmd" (
    SET WLST=%ORACLE_HOME%\oracle_common\common\bin\wlst.cmd
    SET CLASSPATH=%WLSDEPLOY_HOME%\lib\weblogic-deploy-core.jar
    SET WLST_EXT_CLASSPATH=%WLSDEPLOY_HOME%\lib\weblogic-deploy-core.jar
    GOTO found_wlst
)
IF EXIST "%ORACLE_HOME%\wlserver_10.3\common\bin\wlst.cmd" (
    SET WLST=%ORACLE_HOME%\wlserver_10.3\common\bin\wlst.cmd
    SET CLASSPATH=%WLSDEPLOY_HOME%\lib\weblogic-deploy-core.jar
    GOTO found_wlst
)
IF EXIST "%ORACLE_HOME%\wlserver_12.1\common\bin\wlst.cmd" (
    SET WLST=%ORACLE_HOME%\wlserver_12.1\common\bin\wlst.cmd
    SET CLASSPATH=%WLSDEPLOY_HOME%\lib\weblogic-deploy-core.jar
    GOTO found_wlst
)
IF EXIST "%ORACLE_HOME%\wlserver\common\bin\wlst.cmd" (
    IF EXIST "%ORACLE_HOME%\wlserver\.product.properties" (
        @rem WLS 12.1.2 or WLS 12.1.3
        SET WLST=%ORACLE_HOME%\wlserver\common\bin\wlst.cmd
        SET CLASSPATH=%WLSDEPLOY_HOME%\lib\weblogic-deploy-core.jar
    )
    GOTO found_wlst
)

IF NOT EXIST "%WLST%" (
  ECHO Unable to locate wlst.cmd script in ORACLE_HOME %ORACLE_HOME% >&2
  SET RETURN_CODE=98
  GOTO exit_script
)
:found_wlst

SET LOG_CONFIG_CLASS=oracle.weblogic.deploy.logging.WLSDeployCustomizeLoggingConfig
SET WLSDEPLOY_LOG_HANDLER=oracle.weblogic.deploy.logging.SummaryHandler
SET WLST_PROPERTIES=-Dcom.oracle.cie.script.throwException=true
SET "WLST_PROPERTIES=-Djava.util.logging.config.class=%LOG_CONFIG_CLASS% %WLST_PROPERTIES%"
SET "WLST_PROPERTIES=%WLST_PROPERTIES% %WLSDEPLOY_PROPERTIES%"

IF NOT DEFINED WLSDEPLOY_LOG_PROPERTIES (
  SET WLSDEPLOY_LOG_PROPERTIES=%WLSDEPLOY_HOME%\etc\logging.properties
)
IF NOT DEFINED WLSDEPLOY_LOG_DIRECTORY (
  SET WLSDEPLOY_LOG_DIRECTORY=%WLSDEPLOY_HOME%\logs
)
IF NOT DEFINED WLSDEPLOY_LOG_HANDLERS (
  SET WLSDEPLOY_LOG_HANDLERS=%WLSDEPLOY_LOG_HANDLER%
)

ECHO WLSDEPLOY_HOME = %WLSDEPLOY_HOME%
ECHO TESTFILES_PATH =
ECHO JAVA_HOME = %JAVA_HOME%
ECHO WLST_EXT_CLASSPATH = %WLST_EXT_CLASSPATH%
ECHO CLASSPATH = %CLASSPATH%
ECHO WLST_PROPERTIES = %WLST_PROPERTIES%

SET PY_SCRIPTS_PATH=%WLSDEPLOY_HOME%\lib\python

ECHO %WLST% "%PY_SCRIPTS_PATH%\discover.py" %SCRIPT_ARGS%

CALL "%WLST%" "%PY_SCRIPTS_PATH%\discover.py" %SCRIPT_ARGS%

SET RETURN_CODE=%ERRORLEVEL%
IF "%RETURN_CODE%" == "100" (
  GOTO usage
)
IF "%RETURN_CODE%" == "99" (
  GOTO usage
)
IF "%RETURN_CODE%" == "98" (
  ECHO.
  ECHO discoverDomain.cmd failed due to a parameter validation error >&2
  GOTO exit_script
)
IF "%RETURN_CODE%" == "2" (
  ECHO.
  ECHO discoverDomain.cmd failed ^(exit code = %RETURN_CODE%^)
  GOTO exit_script
)
IF "%RETURN_CODE%" == "1" (
  ECHO.
  ECHO discoverDomain.cmd completed but with some issues ^(exit code = %RETURN_CODE%^) >&2
  GOTO exit_script
)
IF "%RETURN_CODE%" == "0" (
  ECHO.
  ECHO discoverDomain.cmd completed successfully ^(exit code = %RETURN_CODE%^)
  GOTO exit_script
)
@rem Unexpected return code so just print the message and exit...
ECHO.
ECHO discoverDomain.cmd failed ^(exit code = %RETURN_CODE%^) >&2
GOTO exit_script

:usage
ECHO.
ECHO Usage: %SCRIPT_NAME% -oracle_home ^<oracle_home^>
ECHO              -domain_home ^<domain_home^>
ECHO              -archive_file ^<archive_file^>
ECHO              [-model_file ^<model_file^>]
ECHO              [-variable_file ^<variable_file^>]
ECHO              [-domain_type ^<domain_type^>]
ECHO              [-wlst_path ^<wlst_path^>]
ECHO              [-java_home ^<java_home^>]
ECHO              [-admin_url ^<admin_url^>
ECHO               -admin_user ^<admin_user^>
ECHO              ]
ECHO.
ECHO     where:
ECHO         oracle_home    - the existing Oracle Home directory for the domain
ECHO.
ECHO         domain_home    - the domain home directory
ECHO.
ECHO         archive_file   - the path to the archive file to create
ECHO.
ECHO         model_file     - the location to write the model file,
ECHO                          the default is to write it inside the archive
ECHO.
ECHO         variable_file  - the location to write properties for attributes that
ECHO                          have been replaced with tokens by the variable injector.
ECHO                          If this is included, all credentials will automatically
ECHO                          be replaced by tokens and the property written to this file.
ECHO.
ECHO         domain_type    - the type of domain (e.g., WLS, JRF).
ECHO                          used to locate wlst.cmd if -wlst_path not specified
ECHO.
ECHO         wlst_path      - the Oracle Home subdirectory of the wlst.cmd
ECHO                          script to use (e.g., ^<ORACLE_HOME^>\soa)
ECHO.
ECHO         java_home      - overrides the JAVA_HOME value when discovering
ECHO                          domain values to be replaced with the java home global token
ECHO.
ECHO         admin_url      - the admin server URL (used for online discovery)
ECHO.
ECHO         admin_user     - the admin username (used for online discovery)
ECHO.

:exit_script
IF DEFINED USE_CMD_EXIT (
  EXIT %RETURN_CODE%
) ELSE (
  EXIT /B %RETURN_CODE%
)

ENDLOCAL
