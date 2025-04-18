@echo off
setlocal

:: Проверяем наличие необходимых инструментов
where iverilog >nul 2>&1
if %errorlevel% neq 0 (
    echo Ошибка: Icarus Verilog (iverilog) не установлен или не добавлен в PATH
    pause
    exit /b 1
)

where vvp >nul 2>&1
if %errorlevel% neq 0 (
    echo Ошибка: Icarus Verilog (vvp) не установлен или не добавлен в PATH
    pause
    exit /b 1
)

:: Компиляция тестбенча
echo Компиляция тестбенча...
iverilog -o ais_sim -g2012 -DIVERILOG ais_transmitter_full.v ais_transmitter_full_tb.v uart_receiver.v

if %errorlevel% neq 0 (
    echo Ошибка компиляции
    pause
    exit /b 1
)

:: Запуск симуляции
echo Запуск симуляции...
vvp ais_sim

if %errorlevel% neq 0 (
    echo Ошибка симуляции
    pause
    exit /b 1
)

:: Открытие VCD файла в GTKWave (если установлен)
where gtkwave >nul 2>&1
if %errorlevel% eq 0 (
    echo Открытие VCD файла в GTKWave...
    start gtkwave ais_transmitter_full.vcd
) else (
    echo GTKWave не установлен, VCD файл не будет открыт автоматически
    echo Вы можете открыть ais_transmitter_full.vcd вручную
)

pause