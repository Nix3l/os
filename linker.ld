ENTRY(boot_enter)
OUTPUT_FORMAT("binary")
SECTIONS {
	. = 0x7c00;
	.text :
	{
        *(.boot)
		*(.text)
	}
}
