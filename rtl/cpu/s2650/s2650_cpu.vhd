--------------------------------------------------------------------------------
-- sgs2650 with std_logic_vector ports for SystemVerilog instantiation
-- ("int" is an SV keyword: the interrupt input is "irq")
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY s2650_cpu IS
  PORT (
    clk    : IN  std_logic;
    reset  : IN  std_logic;
    req    : OUT std_logic;
    ack    : IN  std_logic;
    ad     : OUT std_logic_vector(14 DOWNTO 0);
    wr     : OUT std_logic;
    dw     : OUT std_logic_vector(7 DOWNTO 0);
    dr     : IN  std_logic_vector(7 DOWNTO 0);
    mio    : OUT std_logic;
    ene    : OUT std_logic;
    dc     : OUT std_logic;
    ph     : OUT std_logic_vector(1 DOWNTO 0);
    irq    : IN  std_logic;
    intack : OUT std_logic;
    ivec   : IN  std_logic_vector(7 DOWNTO 0);
    sense  : IN  std_logic;
    flag   : OUT std_logic
    );
END ENTITY s2650_cpu;

ARCHITECTURE rtl OF s2650_cpu IS
  SIGNAL ad_u   : unsigned(14 DOWNTO 0);
  SIGNAL dw_u   : unsigned(7 DOWNTO 0);
  SIGNAL ph_u   : unsigned(1 DOWNTO 0);
  SIGNAL dr_u   : unsigned(7 DOWNTO 0);
  SIGNAL ivec_u : unsigned(7 DOWNTO 0);
BEGIN
  dr_u   <= unsigned(dr);
  ivec_u <= unsigned(ivec);

  cpu : ENTITY work.sgs2650
    PORT MAP (
      req      => req,
      ack      => ack,
      ad       => ad_u,
      wr       => wr,
      dw       => dw_u,
      dr       => dr_u,
      mio      => mio,
      ene      => ene,
      dc       => dc,
      ph       => ph_u,
      int      => irq,
      intack   => intack,
      ivec     => ivec_u,
      sense    => sense,
      flag     => flag,
      reset    => reset,
      clk      => clk,
      reset_na => '1');

  ad <= std_logic_vector(ad_u);
  dw <= std_logic_vector(dw_u);
  ph <= std_logic_vector(ph_u);
END ARCHITECTURE rtl;
