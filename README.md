# Taiko retain_initrd diagnostic

Diagnóstico controlado do Redmi Pad 2 `taiko`. O script:

1. confirma produto, slot, AVB, hash e tamanho;
2. copia `boot_a` para backup no PC;
3. gera localmente uma imagem que difere do original somente pelo argumento `retain_initrd`;
4. grava somente `boot_a`;
5. coleta `/sys/firmware/initrd`, dmesg e pstore se o Android iniciar;
6. restaura e confirma automaticamente o `boot_a` original.

Não formata nem grava userdata, system, vendor_boot ou vbmeta. Se o diagnóstico entrar em bootloop,
entre manualmente em Fastboot e execute o mesmo script com `-Acao restaurar`.
