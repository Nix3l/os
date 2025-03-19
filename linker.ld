ENTRY(boot_enter)
SECTIONS {
	. = 0x7c00;
	.text :
	{
        *(.boot)
		*(.text)
	}
}
