"""Shared DUT-driving helpers for `modexp.v` cocotb testbenches.

`reset()` and `run_modexp()` are the reset sequencing / start-done handshake
/ timeout loop shared, byte-identical, by `test_modexp.py`, `cross_check_tb.py`,
and `repro_out_of_domain_mismatch.py`. Centralizing them here means a future
change to the reset pulse width or the handshake protocol only needs to
happen once instead of being replayed in three files that could otherwise
drift out of sync.

This module is a plain sibling import (`from _dut import reset, run_modexp`),
not a cocotb test module itself -- pytest and cocotb both leave it alone
since it defines no `@cocotb.test()` cases.
"""

from cocotb.triggers import ClockCycles, RisingEdge


async def reset(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.base_in.value = 0
    dut.exp_in.value = 0
    dut.mod_in.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def run_modexp(dut, base, exp, mod, timeout_cycles=20000):
    """Drive one start/done handshake; return the core's result.

    The cycle budget is generous: the core is O(WIDTH^2) -- WIDTH exponent
    steps, each up to two WIDTH-bit interleaved modular multiplies -- so a
    16-bit operand needs a few hundred cycles worst case.
    """
    await RisingEdge(dut.clk)
    dut.base_in.value = base
    dut.exp_in.value = exp
    dut.mod_in.value = mod
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            return int(dut.result.value)
    raise RuntimeError(
        f"modexp({base}, {exp}, {mod}) did not assert done within "
        f"{timeout_cycles} cycles"
    )
