# lib/pg_badger_setup.rb
module PgBadgerSetup
  def self.prepare_for_pg_badger
    puts "\n--- Preparando para pg_badger ---"

    puts "O pg_badger é uma ferramenta externa que analisa logs do PostgreSQL."
    puts "Para usá-lo, você precisa instalá-lo e configurar o PostgreSQL para gerar logs em um formato compatível."

    # Verifica se o pg_badger está instalado (checa se o comando existe no PATH)
    pg_badger_installed = system("which pg_badger > /dev/null 2>&1")

    if pg_badger_installed
      puts "O pg_badger já parece estar instalado no seu sistema."
    else
      puts "O pg_badger não foi encontrado no seu PATH."
      puts "Você precisará instalá-lo manualmente. Aqui estão algumas instruções:"

      case RUBY_PLATFORM
      when /darwin/ # macOS
        puts "  Para macOS (usando Homebrew):"
        puts "    brew install pgbadger"
      when /linux/ # Ubuntu e outras distros Linux
        puts "  Para Ubuntu/Debian:"
        puts "    sudo apt update"
        puts "    sudo apt install pgbadger"
        puts "  Ou para compilar a partir do código-fonte (para outras distros ou se preferir):"
        puts "    # Visite https://pgbadger.darold.net/ para a última versão"
        puts "    # Exemplo: wget https://pgbadger.darold.net/pgbadger-X.X.tar.gz"
        puts "    # tar xzf pgbadger-X.X.tar.gz"
        puts "    # cd pgbadger-X.X"
        puts "    # perl Makefile.PL"
        puts "    # make"
        puts "    # sudo make install"
      else
        puts "  Para outros sistemas operacionais, por favor, consulte a documentação oficial do pg_badger: https://pgbadger.darold.net/"
      end
    end

    puts "Lembre-se de que as configurações de log no `postgresql.conf` (geradas no passo 6) são **essenciais** para que o pg_badger funcione corretamente."
    puts "Após instalar o pg_badger e aplicar as alterações no `postgresql.conf` (e reiniciar o PostgreSQL), você poderá gerar relatórios com um comando como:"
    puts "  pg_badger -f pgbadger -o output.html /path/to/postgresql/log/files/*"
    puts "--- Fim da Preparação para pg_badger ---"
  end
end