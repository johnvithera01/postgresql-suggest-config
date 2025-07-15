# main_script.rb
require_relative 'lib/system_info'
require_relative 'lib/postgresql_config'
require_relative 'lib/pg_badger_setup'
require 'fileutils' # Para operações de arquivo

class EnvironmentAnalyzer
  def run
    puts "Iniciando a análise e configuração do ambiente PostgreSQL..."

    # 1. Verificar a versão do PostgreSQL
    pg_version = PostgreSQLConfig.get_version
    if pg_version.start_with?("Erro") || pg_version.start_with?("Não detectado")
      puts "Erro ou PostgreSQL não detectado. Abortando a configuração."
      return
    end
    puts "Versão do PostgreSQL: #{pg_version}"

    # 2. Verificar tipo de disco (SSD, HDD)
    disk_type = SystemInfo.get_disk_type
    puts "Tipo de disco detectado: #{disk_type}"

    # 3. Quantidade de memória RAM e Swap
    ram_info = SystemInfo.get_ram_info
    swap_info = SystemInfo.get_swap_info
    if ram_info[:total_mb] == 0 || ram_info[:total] == "Erro"
      puts "Erro ao obter informações de RAM. Abortando a configuração."
      return
    end
    puts "Memória RAM: #{ram_info[:total]} (Total), #{ram_info[:free]} (Disponível), #{ram_info[:total_mb].round(2)} MB (Total para cálculos)"
    puts "Swap: #{swap_info[:total]} (Total), #{swap_info[:free]} (Disponível)"

    # 4. Quantidade de núcleos
    cpu_cores = SystemInfo.get_cpu_cores
    if cpu_cores.to_s.start_with?("Erro") || cpu_cores == 0
      puts "Erro ao obter número de núcleos da CPU. Abortando a configuração."
      return
    end
    puts "Número de núcleos da CPU: #{cpu_cores}"

    # 5. Preparar para usar pg_badger (apenas instruções de instalação e log)
    PgBadgerSetup.prepare_for_pg_badger

    # 6. Gerar e aplicar alterações no postgresql.conf
    puts "\n--- Geração do postgresql.conf recomendado ---"
    recommended_config_content = PostgreSQLConfig.generate_recommendations(
      pg_version: pg_version,
      disk_type: disk_type,
      ram_total_mb: ram_info[:total_mb],
      cpu_cores: cpu_cores
    )

    # Localizar o postgresql.conf atual
    pg_config_path = PostgreSQLConfig.find_postgresql_conf_path
    if pg_config_path == "Não encontrado"
      puts "Atenção: Não foi possível localizar o postgresql.conf automaticamente."
      puts "As recomendações foram impressas. Por favor, aplique-as manualmente no seu arquivo de configuração."
      # Salva o arquivo recomendado em um local temporário mesmo assim
      output_filename = "postgresql_recommended_#{Time.now.strftime('%Y%m%d_%H%M%S')}.conf"
      File.write(output_filename, recommended_config_content)
      puts "Um arquivo com as recomendações foi salvo como '#{output_filename}'."
    else
      puts "Arquivo postgresql.conf encontrado em: #{pg_config_path}"
      backup_path = "#{pg_config_path}.bak_#{Time.now.strftime('%Y%m%d_%H%M%S')}"

      # Criar backup
      begin
        FileUtils.cp(pg_config_path, backup_path)
        puts "Backup do arquivo original criado em: #{backup_path}"
      rescue => e
        puts "Erro ao criar backup do arquivo original: #{e.message}"
        puts "Recomendações impressas. Abortando a modificação automática do arquivo."
        # Salva o arquivo recomendado em um local temporário mesmo assim
        output_filename = "postgresql_recommended_#{Time.now.strftime('%Y%m%d_%H%M%S')}.conf"
        File.write(output_filename, recommended_config_content)
        puts "Um arquivo com as recomendações foi salvo como '#{output_filename}'."
        return
      end

      # Gerar diff
      diff = PostgreSQLConfig.generate_diff(pg_config_path, recommended_config_content)
      if diff.empty?
        puts "Nenhuma diferença significativa entre o arquivo atual e as recomendações."
      else
        puts "\n--- Diferenças sugeridas para postgresql.conf (diff) ---"
        puts diff
        puts "--- Fim do Diff ---"

        puts "\n❓ Deseja criar um novo arquivo 'postgresql_new.conf' com as recomendações? (s/n)"
        answer = STDIN.gets.chomp.downcase
        if answer == 's'
          new_config_path = File.join(File.dirname(pg_config_path), "postgresql_new.conf")
          File.write(new_config_path, recommended_config_content)
          puts "Novo arquivo de configuração gerado em: #{new_config_path}"
          puts "Por favor, revise '#{new_config_path}' e, se estiver satisfeito, considere substituir o '#{pg_config_path}' original por ele."
          puts "Lembre-se de **reiniciar o serviço do PostgreSQL** para que as novas configurações entrem em vigor."
        else
          puts "Nenhuma alteração feita no arquivo. As recomendações foram apenas impressas acima."
        end
      end
    end

    puts "\nAnálise do ambiente concluída."
    puts "Para que as novas configurações de log e de recursos do PostgreSQL entrem em vigor, você deve **reiniciar o serviço do PostgreSQL**."
    puts "Exemplo (Ubuntu): sudo systemctl restart postgresql"
    puts "Exemplo (macOS Homebrew): brew services restart postgresql"
  end
end

EnvironmentAnalyzer.new.run