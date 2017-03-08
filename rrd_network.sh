#!/bin/bash
#
# Copyright 2016 Sandro Marcell <smarcell@mail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
PATH='/bin:/sbin:/usr/bin:/usr/sbin'
LC_ALL='pt_BR.UTF-8'

# Diretorio onde serao armazenadas as bases de dados do rrdtool
BD_RRD='/var/lib/rrd/rrd-network'

# Diretorio no servidor web onde serao armazenados os arquivos html/png gerados
DIR_HTML='/var/www/html/rrd-network'

# Gerar os graficos para os seguintes periodos de tempo
PERIODOS='day week month year'

# Intervalo de atualizacao das paginas html (padrao 5 minutos)
INTERVALO=$((60 * 5))

# Interfaces de rede que serao monitoradas
# Este vetor deve ser definido da seguinte forma:
# <interface1> <descricao> <interface2> <descricao> <interface3> <descricao> ...
# Ex.: Supondo que seu servidor possua tres interfaces de rede, onde
# eth0 = Link para a internet
# eth1 = Link da LAN
# eth2 = Link para a DMZ
# entao faca:
# INTERFACES=('eth0' 'Link internet' 'eth1' 'Link LAN' 'eth2' 'Link DMZ')
INTERFACES=('lo' 'Loopback' 'eth0' 'Link internet')

# Criando os diretorios de trabalho caso nao existam
[ ! -d "$BD_RRD" ] && { mkdir -p "$BD_RRD" || exit 1; }
[ ! -d "$DIR_HTML" ] && { mkdir -p "$DIR_HTML" || exit 1; }

# Funcao principal que sera a responsavel geracao dos graficos
function gerarGraficos {
	declare -a args=("${INTERFACES[@]}")
	declare iface=''
	declare desc=''
	declare rx_bytes=0
	declare tx_bytes=0

	while [ ${#args[@]} -ne 0 ]; do
		iface="${args[0]}" # Interface a ser monitorada
		desc="${args[1]}"  # Descricao da interface monitorada
		args=("${args[@]:2}") # Descartando os dois elementos ja lidos do vetor

		# Coletando os valores recebidos/enviados pela interface
		# Obs.: Os valores sao coletados em bytes mas ao se gerar
		# os graficos, esses dados serao convertidos em bits
		rx_bytes=$(</sys/class/net/$iface/statistics/rx_bytes)
		tx_bytes=$(</sys/class/net/$iface/statistics/tx_bytes)

		# Caso as bases rrd nao existam, entao serao criadas e cada uma
		# tera o mesmo nome da interface monitorada
		if [ ! -e "${BD_RRD}/${iface}.rrd" ]; then
			# Armazenar valores de acordo com os peridos definidos em $PERIODO
			# e computados com base no intervalo de $INTERVALO
			v30min=$((INTERVALO * 2 / 30))  # Semanal
			v2hrs=$((INTERVALO * 2 / 120))  # Mensal
			v1d=$((1440 / (INTERVALO * 2))) # Anual
			
			echo "Criando base de dados rrd: ${BD_RRD}/${iface}.rrd"
			rrdtool create ${BD_RRD}/${iface}.rrd --start 0 --step $INTERVALO \
				DS:in:DERIVE:$((INTERVALO * 2)):0:U \
				DS:out:DERIVE:$((INTERVALO * 2)):0:U \
				RRA:MIN:0.5:1:1500 \
				RRA:MIN:0.5:$v30min:1500 \
				RRA:MIN:0.5:$v2hrs:1500 \
				RRA:MIN:0.5:$v1d:1500 \
				RRA:AVERAGE:0.5:1:1500 \
				RRA:AVERAGE:0.5:$v30min:1500 \
				RRA:AVERAGE:0.5:$v2hrs:1500 \
				RRA:AVERAGE:0.5:$v1d:1500 \
				RRA:MAX:0.5:1:1500 \
				RRA:MAX:0.5:$v30min:1500 \
				RRA:MAX:0.5:$v2hrs:1500 \
				RRA:MAX:0.5:$v1d:1500
			[ $? -gt 0 ] && return 1
		fi

		# Se as bases ja existirem, entao atualize-as...
		echo "Atualizando base de dados: ${BD_RRD}/${iface}.rrd"
		rrdtool update ${BD_RRD}/${iface}.rrd --template in:out N:${rx_bytes}:$tx_bytes
		[ $? -gt 0 ] && return 1

		# e depois gere os graficos
		for i in $PERIODOS; do
			case $i in
				  'day') tipo='Média diária (5 minutos)'   ;;
				 'week') tipo='Média semanal (30 minutos)' ;;
				'month') tipo='Média mensal (2 horas)'     ;;
				 'year') tipo='Média anual (1 dia)'        ;;
			esac

			rrdtool graph ${DIR_HTML}/${iface}_${i}.png --base=1000 --start -1$i --font='TITLE:0:Bold' --title="$desc ($iface) / $tipo" \
				--lazy --watermark="$(date "+%c")" --vertical-label='Bits por segundo' --slope-mode --alt-y-grid --rigid \
				--height=124 --width=550 --lower-limit=0 --imgformat=PNG \
				--color='BACK#FFFFFF' --color='SHADEA#FFFFFF' --color='SHADEB#FFFFFF' \
				--color='MGRID#AAAAAA' --color='GRID#CCCCCC' --color='ARROW#333333' \
				--color='FONT#333333' --color='AXIS#333333' --color='FRAME#333333' \
				DEF:in_bytes=${BD_RRD}/${iface}.rrd:in:AVERAGE \
				DEF:out_bytes=${BD_RRD}/${iface}.rrd:out:AVERAGE \
				CDEF:in_bits=in_bytes,8,* \
				CDEF:out_bits=out_bytes,8,* \
				VDEF:min_in=in_bits,MINIMUM \
				VDEF:min_out=out_bits,MINIMUM \
				VDEF:max_in=in_bits,MAXIMUM \
				VDEF:max_out=out_bits,MAXIMUM \
				VDEF:avg_in=in_bits,AVERAGE \
				VDEF:avg_out=out_bits,AVERAGE \
				"COMMENT:$(printf "%21s")" \
				"COMMENT:Mínimo$(printf "%7s")" \
				"COMMENT:Máximo$(printf "%7s")" \
				COMMENT:"Média\l" \
				"COMMENT:$(printf "%5s")" \
				"AREA:out_bits#FE2E2E95:Upload$(printf "%4s")" \
				LINE1:out_bits#FE2E2E95 \
				"GPRINT:min_out:%5.1lf %sbps$(printf "%3s")" \
				"GPRINT:max_out:%5.1lf %sbps$(printf "%3s")" \
				"GPRINT:avg_out:%5.1lf %sbps$(printf "%3s")\l" \
				"COMMENT:$(printf "%5s")" \
				"AREA:in_bits#2E64FE95:Download$(printf "%2s")" \
				LINE1:in_bits#2E64FE95 \
				"GPRINT:min_in:%5.1lf %sbps$(printf "%3s")" \
				"GPRINT:max_in:%5.1lf %sbps$(printf "%3s")" \
				"GPRINT:avg_in:%5.1lf %sbps$(printf "%3s")\l" 1> /dev/null
			[ $? -gt 0 ] && return 1
		done
	done
	return 0
}

# Funcao que ira criar as paginas html
function criarPaginasHTML {
	declare -a ifaces
	local titulo='Gr&aacute;ficos estat&iacute;sticos de tr&aacute;fego de rede'

	# Filtrando o vetor $INTERFACES para retornar somente as interfaces de rede
	for ((i = 0; i <= ${#INTERFACES[@]}; i++)); do
		((i % 2 == 0)) && ifaces+=("${INTERFACES[$i]}")
	done

	echo 'Criando paginas HTML...'

	# 1o: Criar a pagina index
	cat <<- FIM > ${DIR_HTML}/index.html
	<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
	"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
	<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
	<head>
	<title>${0##*/}</title>
	<meta http-equiv="content-type" content="text/html;charset=utf-8" />
	<meta http-equiv="refresh" content="$INTERVALO" />
	<meta name="author" content="Sandro Marcell" />
	<style type="text/css">
		body { margin: 0; padding: 0; background-color: #AFBFCB; width: 100%; height: 100%; font: 20px/1.5em Helvetica, Arial, sans-serif; }
		a:link, a:hover, a:active { text-decoration: none; color: #AFBFCB; }
		#header { text-align: center; }
		#content { position: relative; text-align: center; margin: auto; }
		#footer { font-size: 10px; text-align: center; }
	</style>
	</head>
	<body>
		<div id="header">
			<p>$titulo<br /><small>(Host: $(hostname))</small></p>
		</div>
		<div id="content">
			<script type="text/javascript">
				$(for i in ${ifaces[@]}; do
					echo "document.write('<div><a href="\"${i}.html\"" title="\"* Clique para ver mais detalhes.\""><img src="\"${i}_day.png?nocache=\' + Math.random\(\) + \'\"" alt="\"${0##*/} --html\"" /></a></div>');"
				done)
			</script>
		</div>
		<div id="footer">
			<p>${0##*/} &copy; 2016 Sandro Marcell</p>
		</div>
	</body>
	</html>
	FIM

	# 2o: Criar pagina especifica para cada interface com os periodos definidos
	for i in ${ifaces[@]}; do
		cat <<- FIM > ${DIR_HTML}/${i}.html
		<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
		"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
		<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
		<head>
		<title>${0##*/}</title>
		<meta http-equiv="content-type" content="text/html;charset=utf-8" />
		<meta http-equiv="refresh" content="$INTERVALO" />
		<meta name="author" content="Sandro Marcell" />
		<style type="text/css">
			body { margin: 0; padding: 0; background-color: #AFBFCB; width: 100%; height: 100%; font: 20px/1.5em Helvetica, Arial, sans-serif; }
			#header { text-align: center; }
			#content { position: relative; text-align: center; margin: auto; }
			#footer { font-size: 10px; text-align: center; }
		</style>
		</head>
		<body>
			<div id="header">
				<p>$titulo<br /><small>(Host: $(hostname))</small></p>
			</div>
			<div id="content">
				<script type="text/javascript">
					$(for p in $PERIODOS; do
						echo "document.write('<div><img src="\"${i}_${p}.png?nocache=\' + Math.random\(\) + \'\"" alt="\"${0##*/} --html\"" /></div>');"
					done)
				</script>
			</div>
			<div id="footer">
				<a href="index.html">Voltar</a>
				<p>${0##*/} &copy; 2016 Sandro Marcell</p>
			</div>
		</body>
		</html>
		FIM
	done
	return 0
}

# Criar os arquivos html se for o caso
# Chamada do script: rrd_network.sh --html
if [ "$1" == '--html' ]; then
	criarPaginasHTML
	exit 0
fi

# Coletando dados e gerando os graficos
# Chamada do script: rrd_network.sh
gerarGraficos
