library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity selector is
generic(
	PEND_THRESH : integer := 1;
	ADDR_LMT : integer := 20;
	MDATA : integer := 14);
port(
	Clk_32UI : in std_logic;
	Resetb : in std_logic;

	ab2re_WrAddr : out std_logic_vector(ADDR_LMT-1 downto 0);
	ab2re_WrTID : out std_logic_vector(13 downto 0);
	ab2re_WrDin : out std_logic_vector(511 downto 0);
	ab2re_WrFence : out std_logic;
	ab2re_WrEn : out std_logic;
	re2ab_WrSent : in std_logic;
	re2ab_WrAlmFull : in std_logic;

	ab2re_RdAddr : out std_logic_vector(ADDR_LMT-1 downto 0);
	ab2re_RdTID : out std_logic_vector(13 downto 0);
	ab2re_RdEn : out std_logic;
	re2ab_RdSent : in std_logic;

	re2ab_RdRspValid : in std_logic;
	re2ab_UMsgValid : in std_logic;
	re2ab_CfgValid : in std_logic;
	re2ab_RdRsp : in std_logic_vector(13 downto 0);
	re2ab_RdData : in std_logic_vector(511 downto 0);
	re2ab_stallRd : in std_logic;

	re2ab_WrRspValid : in std_logic;
	re2ab_WrRsp : in std_logic_vector(13 downto 0);

	re2xy_go : in std_logic;
	re2xy_src_addr : in std_logic_vector(31 downto 0);
	re2xy_dst_addr : in std_logic_vector(31 downto 0);
	re2xy_NumLines : in std_logic_vector(31 downto 0);
	re2xy_expected_NumLines : in std_logic_vector(31 downto 0);
	re2xy_addr_reset : in std_logic_vector(31 downto 0);
	re2xy_read_offset : in std_logic_vector(31 downto 0);
	re2xy_write_offset : in std_logic_vector(31 downto 0);
	re2xy_dummy_key : in std_logic_vector(31 downto 0);
	re2xy_radix_bits : in std_logic_vector(31 downto 0);
	re2xy_Cont : in std_logic;
	re2xy_test_cfg : in std_logic_vector(7 downto 0);
	re2ab_Mode : in std_logic_vector(2 downto 0);

	ab2re_TestCmp : out std_logic;
	ab2re_ErrorInfo : out std_logic_vector(255 downto 0);
	ab2re_ErrorValid : out std_logic;

	test_Resetb : std_logic);
end selector;

architecture behavioral of selector is

constant RspAddr : std_logic_vector(ADDR_LMT-1 downto 0) := (others => '0');

signal reset_NumberOfReadCacheLines : std_logic;
signal NumberOfReadCacheLines : unsigned(ADDR_LMT-1 downto 0) := (others => '0');

signal decomp_en : std_logic;

signal decomp_out_valid : std_logic;
signal decomp_out_data : std_logic_vector(511 downto 0);
signal decomp_out_almostfull : std_logic;
signal decomp_fifos_free_count : std_logic_vector(31 downto 0);
signal decomp_send_disable : std_logic;
signal partitioner_data_valid : std_logic;
signal partitioner_data : std_logic_vector(511 downto 0);

component partitioner3
generic(
	PEND_THRESH : integer := 1;
	ADDR_LMT : integer := 20;
	MDATA : integer := 14;
	MAX_RADIX_BITS : integer := 13);
port(
	Clk_32UI : in std_logic;
	Resetb : in std_logic;

	l12ab_WrAddr : 		out std_logic_vector(ADDR_LMT-1 downto 0);	--write address
	l12ab_WrTID :		out std_logic_vector(13 downto 0);			--meta data
	l12ab_WrDin :		out std_logic_vector(511 downto 0);			--cache line data
	l12ab_WrEn :		out std_logic;								--write enable
	ab2l1_WrSent :		in std_logic;								--write issued
	ab2l1_WrAlmFull :	in std_logic;								--write fifo almost full

	l12ab_RdAddr :		out std_logic_vector(ADDR_LMT-1 downto 0);	--reads may yield to writes
	l12ab_RdTID :		out std_logic_vector(13 downto 0);			--meta data
	l12ab_RdEn :		out std_logic;								--read enable
	ab2l1_RdSent :		in std_logic;								--read issued

	ab2l1_RdRspValid :	in std_logic;								--read response valid
	ab2l1_CfgValid : 	in std_logic;
	ab2l1_RdRsp :		in std_logic_vector(13 downto 0);			--read response header
	ab2l1_RdRspAddr : 	in std_logic_vector(ADDR_LMT-1 downto 0);	--read response address
	ab2l1_RdData :		in std_logic_vector(511 downto 0);			--read data
	ab2l1_stallRd :		in std_logic;								--stall read requests FOR LPBK1

	ab2l1_WrRspValid :	in std_logic;								--write response valid
	ab2l1_WrRsp :		in std_logic_vector(13 downto 0);			--write response header
	ab2l1_WrRspAddr :	in std_logic_vector(ADDR_LMT-1 downto 0);	--write response address

	re2xy_go : 			in std_logic;								--start the test
	re2xy_src_addr : 	in std_logic_vector(31 downto 0);
	re2xy_dst_addr : 	in std_logic_vector(31 downto 0);
	re2xy_NumLines :	in std_logic_vector(31 downto 0);			--number of cache lines
	re2xy_expected_NumLines :	in std_logic_vector(31 downto 0);
	re2xy_addr_reset : 		in std_logic_vector(31 downto 0);
	re2xy_read_offset : 	in std_logic_vector(31 downto 0);
	re2xy_write_offset : 	in std_logic_vector(31 downto 0);
	re2xy_dummy_key :		in std_logic_vector(31 downto 0);
	re2xy_radix_bits :		in std_logic_vector(31 downto 0);
	re2xy_Cont :		in std_logic;								--continuous mode
	re2xy_test_cfg : in std_logic_vector(7 downto 0);

	read_NumLines : 	in std_logic_vector(31 downto 0);
	reset_read_NumLines : out std_logic;
	decomp_almostfull : in std_logic;
	decomp_fifos_free_count : in std_logic_vector(31 downto 0);
	decomp_stop_sending : out std_logic;
	l12ab_TestCmp : 	out std_logic;								--test completion flag
	l12ab_ErrorInfo :	out std_logic_vector(255 downto 0);			--error information
	l12ab_ErrorValid :	out std_logic;								--test has detected an error

	test_Resetb : 		in std_logic);
end component;

component generator is
port (
	clk : in std_logic;
	resetn : in std_logic;

	in_enable : in std_logic;
	in_start : in std_logic;
	in_send_disable : in std_logic;
	in_number_of_lines_to_generate : in std_logic_vector(31 downto 0);
	out_valid : out std_logic;
	out_data : out std_logic_vector(511 downto 0));
end component;

begin

g: generator
port map (
	clk => Clk_32UI,
	resetn => test_Resetb,

	in_enable => decomp_en,
	in_start => re2xy_go,
	in_send_disable => decomp_send_disable,
	in_number_of_lines_to_generate => re2xy_expected_NumLines,
	out_valid => decomp_out_valid,
	out_data => decomp_out_data
);

partitioner: partitioner3
generic map (
	PEND_THRESH => PEND_THRESH,
	ADDR_LMT => ADDR_LMT,
	MDATA => MDATA,
	MAX_RADIX_BITS => 13)
port map (
	Clk_32UI => Clk_32UI,
	Resetb => Resetb,

	l12ab_WrAddr => ab2re_WrAddr,
	l12ab_WrTID => ab2re_WrTID,
	l12ab_WrDin => ab2re_WrDin,
	l12ab_WrEn => ab2re_WrEn,
	ab2l1_WrSent => re2ab_WrSent,
	ab2l1_WrAlmFull => re2ab_WrAlmFull,

	l12ab_RdAddr => ab2re_RdAddr,
	l12ab_RdTID => ab2re_RdTID,
	l12ab_RdEn => ab2re_RdEn,
	ab2l1_RdSent => re2ab_RdSent,

	ab2l1_RdRspValid => partitioner_data_valid,
	ab2l1_CfgValid => re2ab_CfgValid,
	ab2l1_RdRsp => re2ab_RdRsp,
	ab2l1_RdRspAddr => RspAddr,
	ab2l1_RdData => partitioner_data,
	ab2l1_stallRd => re2ab_stallRd,

	ab2l1_WrRspValid => re2ab_WrRspValid,
	ab2l1_WrRsp => re2ab_WrRsp,
	ab2l1_WrRspAddr => RspAddr,

	re2xy_go => re2xy_go,
	re2xy_src_addr => re2xy_src_addr,
	re2xy_dst_addr => re2xy_dst_addr,
	re2xy_NumLines => re2xy_NumLines,
	re2xy_expected_NumLines => re2xy_expected_NumLines,
	re2xy_addr_reset => re2xy_addr_reset,
	re2xy_read_offset => re2xy_read_offset,
	re2xy_write_offset => re2xy_write_offset,
	re2xy_dummy_key => re2xy_dummy_key,
	re2xy_radix_bits => re2xy_radix_bits,
	re2xy_Cont => re2xy_Cont,
	re2xy_test_cfg => re2xy_test_cfg,

	read_NumLines => std_logic_vector(NumberOfReadCacheLines),
	reset_read_NumLines => reset_NumberOfReadCacheLines,
	decomp_almostfull => decomp_out_almostfull,
	decomp_fifos_free_count => decomp_fifos_free_count,
	decomp_stop_sending => decomp_send_disable,
	l12ab_TestCmp => ab2re_TestCmp,
	l12ab_ErrorInfo => ab2re_ErrorInfo,
	l12ab_ErrorValid => ab2re_ErrorValid,

	test_Resetb => test_Resetb
);

decomp_out_almostfull <= '0';
decomp_fifos_free_count <= (others => '1');

partitioner_data_valid <= re2ab_RdRspValid when decomp_en = '0' else
						  decomp_out_valid;
partitioner_data <= re2ab_RdData when decomp_en = '0' else
					decomp_out_data;

ab2re_WrFence <= '0';

process(Clk_32UI)
begin
if Clk_32UI'event and Clk_32UI = '1' then
	if test_Resetb = '0' then
		NumberOfReadCacheLines <= (others => '0');

		decomp_en <= '0';
	else
		if re2xy_Cont = '1' then
			decomp_en <= '1';
		else
			decomp_en <= '0';
		end if;

		if re2ab_RdRspValid = '1' then
			NumberOfReadCacheLines <= NumberOfReadCacheLines + 1;
		end if;
		if reset_NumberOfReadCacheLines = '1' then
			NumberOfReadCacheLines <= (others => '0');
		end if;
	end if;
end if;
end process;

end architecture;