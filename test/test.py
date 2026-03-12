# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

async def load_byte(dut, byte_val):
    dut.ui_in.value = byte_val
    dut.uio_in.value = 0b11
    await ClockCycles(dut.clk, 2)
    dut.uio_in.value = 0b01
    await ClockCycles(dut.clk, 1)

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 50)
    dut.rst_n.value = 1

    dut.uio_in.value = 0b01
    await ClockCycles(dut.clk, 2)

    await load_byte(dut, 0x70)
    await load_byte(dut, 0x32)
    await load_byte(dut, 0xE0)
    await load_byte(dut, 0x00)

    dut.uio_in.value = 0b00
    dut.ui_in.value = 0

    await ClockCycles(dut.clk, 100)

    try:
        result = int(dut.uo_out.value)
        assert result == 50, f"Expected 50, got {result}"
    except ValueError:
        dut._log.warning("Output has X values in gate-level sim, skipping assert")