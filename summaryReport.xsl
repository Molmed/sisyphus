<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" doctype-system="http://www.w3.org/TR/html4/strict.dtd" doctype-public="-//W3C//DTD HTML 4.01//EN" indent="yes" />

  <xsl:template name="RepeatString">
    <xsl:param name="string" select="''" />
    <xsl:param name="times"  select="1" />
    <xsl:if test="number($times) &gt; 0">
      <xsl:value-of select="$string" />
      <xsl:call-template name="RepeatString">
	<xsl:with-param name="string" select="$string" />
	<xsl:with-param name="times"  select="$times - 1" />
      </xsl:call-template>
    </xsl:if>
  </xsl:template>

  <xsl:template name="format-suffix">
    <xsl:param name="myval" />
    <xsl:param name="precision" />

    <xsl:variable name="zeroes">
      <xsl:call-template name="RepeatString">
	<xsl:with-param name="string" select="0" />
	<xsl:with-param name="times"  select="$precision" />
      </xsl:call-template>
    </xsl:variable>

    <xsl:variable name="dval" select="concat(1,$zeroes)" />

    <xsl:choose>
      <xsl:when test="$myval &gt; 1000000000">
	<xsl:value-of select="format-number(round($myval div (1000000000 div $dval)) div $dval, concat('#.',$zeroes))" />
	<xsl:text>G</xsl:text>
      </xsl:when>
      <xsl:when test="$myval &gt; 1000000">
	<xsl:value-of select="format-number(round($myval div (1000000 div $dval)) div $dval, concat('#.',$zeroes))" />
	<xsl:text>M</xsl:text>
      </xsl:when>
      <xsl:when test="$myval &gt; 1000">
	<xsl:value-of select="format-number(round($myval div (1000 div $dval)) div $dval, concat('#.',$zeroes))" />
	<xsl:text>k</xsl:text>
      </xsl:when>
      <xsl:otherwise>
	<xsl:value-of select="$myval" />
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template match="/SummaryReport">
    <html>
      <head>
        <title><xsl:value-of select="MetaData/@RunFolder"/></title>
        <style type="text/css">
          body {font:12px arial,sans-serif; background:#ffffff}
          h1 {text-align: left; padding: 5px; font-weight:bold; font-size:150%;}
          h2 {text-align: left; padding: 5px; font-weight:bold; font-size:120%;}
          hr {color:sienna;}
          p {margin-left:20px; width: 80em;}
          tr.even { background: #bbbbbb; }
          tr.odd { background: #dddddd; }
          thead { background: #eeeeee; }
          div.section {display: inline-block; background: #eeeeee; margin-bottom: 20px; margin-right: 20px;}
          table th { padding: 1px 10px;}
          table td { padding: 1px 10px;}
          table td { text-align: center;}
          table tr.SampleName { background: #aaaaaa; }
          table td.SampleName { text-align: left; padding:10px 5px 5px 5px; font-weight:bold; font-size:125%;}
          span.stddev {font-size:75%;}
          table.MetaData th { text-align: left; padding: 5px; font-weight:bold; font-size:100%;}
          table.MetaData td { text-align: left; padding: 5px; font-size:75%; background:#dddddd}
          table.key th { text-align: left; padding: 5px; font-size:75%;}
          table.key td { text-align: left; padding: 5px; font-size:75%; background:#dddddd}
        </style>

      </head>
      <body>
        <h1>Summary of sequencing results for <xsl:value-of select="MetaData/@RunFolder"/></h1>
        <br />
        <div>
	  <div class="section">
	    <h2>Metrics aggregated per lane</h2>
	    <table>
	      <thead>
		<tr>
		  <th>Lane</th>
		  <th>Raw Density<br/>clusters/mm<sup>2</sup></th>
		  <th>Excluded<br /> Tiles</th>
		  <th>Pass<br/>Filter(%)</th>
		  <th>Clusters<br/>PF</th>
		  <th>Read</th>
		  <th>Yield<br/>PF (bp)</th>
		  <th>Q&#8805;30(%)</th>
		  <th>Yield<br/>Q&#8805;30 (bp)</th>
		  <th>MeanQ</th>
                  <th>Q-score per base<br />A/C/G/T</th>
		  <th>PhiX<br/>Error<br />(Excluded)</th>
		  <th>Q-score<br/>distribution</th>
		  <th>Base<br/>composition</th>
		  <th>GC<br/>distribution</th>
		  <th>Contiguous Length<br/>with Q&#8805;30 (bp)</th>
		  <th>Duplicates</th>
		  <th>Adapter<br/>sequences</th>
                  <th>Q-score per base<br/>and position</th>
		</tr>
	      </thead>
	      <tbody>
		<xsl:for-each select="LaneMetrics/Lane">
		  <xsl:variable name="row-class">
		    <xsl:choose>
		      <xsl:when test="position() mod 2 = 0">even</xsl:when>
		      <xsl:otherwise>odd</xsl:otherwise>
		    </xsl:choose>
		  </xsl:variable>

		  <xsl:variable name="LaneRows">
		    <xsl:value-of select="count(descendant::Read)"/>
		  </xsl:variable>

		  <xsl:for-each select="./Read">
		    <tr class="{$row-class}">
		      <xsl:if test="count(preceding-sibling::Read) = 0">
			<td rowspan="{$LaneRows}"><xsl:value-of select="../@Id"/></td>
			<td rowspan="{$LaneRows}">
			  <xsl:call-template name="format-suffix">
			    <xsl:with-param name="myval" select="@DensityRaw" />
			    <xsl:with-param name="precision" select="1" />
			  </xsl:call-template>
			</td>
			<td rowspan="{$LaneRows}">
			  <xsl:call-template name="format-suffix">
			    <xsl:with-param name="myval" select="@ExcludedTiles" />
			    <xsl:with-param name="precision" select="1" />
			  </xsl:call-template>
			</td>
			<td rowspan="{$LaneRows}"><xsl:value-of select="@PctPF"/></td>
			<td rowspan="{$LaneRows}">
			  <xsl:attribute name="style">
			    <xsl:choose>
			      <xsl:when test="@PF &lt; 140000000">
				<xsl:text>background: #ff7777; color: black;</xsl:text>
			      </xsl:when>
			    </xsl:choose>
			  </xsl:attribute>
			  <xsl:call-template name="format-suffix">
			    <xsl:with-param name="myval" select="@PF" />
			    <xsl:with-param name="precision" select="1" />
			  </xsl:call-template>
			</td>
		      </xsl:if>
		      <td><xsl:value-of select="@Id"/></td>
			<td>
			  <xsl:call-template name="format-suffix">
			    <xsl:with-param name="myval" select="@YieldPF" />
			    <xsl:with-param name="precision" select="1" />
			  </xsl:call-template>
			</td>

<!--		      <td><xsl:value-of select="@Q30Fraction"/></td>-->
		      <td><xsl:value-of select="format-number(round((@YieldQ30 * 1000) div @YieldPF) div 10, '##.0')"/></td>
		      <td>
			<xsl:call-template name="format-suffix">
			  <xsl:with-param name="myval" select="@YieldQ30" />
			  <xsl:with-param name="precision" select="1" />
			</xsl:call-template>
		      </td>

		      <td><xsl:value-of select="@QMean"/><span class="stddev">&#177;<xsl:value-of select="@QStdDev"/></span></td>
		      <td>
                         <xsl:value-of select="@QValuePerBaseAMean"/><span class="stddev">&#177;<xsl:value-of select="@QValuePerBaseAStdv"/></span><br/>
                         <xsl:value-of select="@QValuePerBaseCMean"/><span class="stddev">&#177;<xsl:value-of select="@QValuePerBaseCStdv"/></span><br/>
                         <xsl:value-of select="@QValuePerBaseGMean"/><span class="stddev">&#177;<xsl:value-of select="@QValuePerBaseGStdv"/></span><br/>
                         <xsl:value-of select="@QValuePerBaseTMean"/><span class="stddev">&#177;<xsl:value-of select="@QValuePerBaseTStdv"/></span>
                       </td>
                      <td>
			<xsl:attribute name="style">
			  <xsl:choose>
			    <xsl:when test="@ErrRate &gt; 2">
			      <xsl:text>background: #ff7777; color: black;</xsl:text>
			    </xsl:when>
			  </xsl:choose>
			</xsl:attribute>
			<xsl:value-of select="@ErrRate"/>
			<span class="stddev">&#177;<xsl:value-of select="@ErrRateSD"/></span>
			<xsl:if test="@ExcludedTiles > 0">
			  <br />(
			  <xsl:value-of select="Excluded/@ErrRate"/>
			  <span class="stddev">&#177;<xsl:value-of select="Excluded/@ErrRateSD"/></span>
			  )
			</xsl:if>

		      </td>

		      <xsl:choose>
			<xsl:when test="@QscorePlot = &apos;NA&apos;">
			  <td>NA</td>
			</xsl:when>
			<xsl:otherwise>
			  <td><a href="{concat('./',@QscorePlot)}"><img alt="Qscore Plot" src="{concat('./',@QscorePlotThumb)}"/></a></td>
			</xsl:otherwise>
		      </xsl:choose>

		      <xsl:choose>
			<xsl:when test="@BaseCompPlot = &apos;NA&apos;">
			  <td>NA</td>
			</xsl:when>
			<xsl:otherwise>
			  <td><a href="{concat('./',@BaseCompPlot)}"><img alt="Base Composition Plot" src="{concat('./',@BaseCompPlotThumb)}"/></a></td>
			</xsl:otherwise>
		      </xsl:choose>

		      <xsl:choose>
			<xsl:when test="@GCPlot = &apos;NA&apos;">
			  <td>NA</td>
			</xsl:when>
			<xsl:otherwise>
			  <td><a href="{concat('./',@GCPlot)}"><img alt="GC Plot" src="{concat('./',@GCPlotThumb)}"/></a></td>
			</xsl:otherwise>
		      </xsl:choose>

		      <xsl:choose>
			<xsl:when test="@Q30Plot = &apos;NA&apos;">
			  <td>NA</td>
			</xsl:when>
			<xsl:otherwise>
			  <td><a href="{concat('./',@Q30Plot)}"><img alt="Q30Length Plot" src="{concat('./',@Q30PlotThumb)}"/></a></td>
			</xsl:otherwise>
		      </xsl:choose>

		      <xsl:choose>
			<xsl:when test="@DupPlot = &apos;NA&apos;">
			  <td>NA</td>
			</xsl:when>
			<xsl:otherwise>
			  <td><a href="{concat('./',@DupPlot)}"><img alt="Duplication Plot" src="{concat('./',@DupPlotThumb)}"/></a></td>
			</xsl:otherwise>
		      </xsl:choose>

		      <xsl:choose>
			<xsl:when test="@AdapterPlot = &apos;NA&apos;">
			  <td>NA</td>
			</xsl:when>
			<xsl:otherwise>
			  <td><a href="{concat('./',@AdapterPlot)}"><img alt="Adapter Plot" src="{concat('./',@AdapterPlotThumb)}"/></a></td>
			</xsl:otherwise>
		      </xsl:choose>

                      <xsl:choose>
                       <xsl:when test="@QValuePerBase = &apos;NA&apos;">
                         <td>NA</td>
                       </xsl:when>
                       <xsl:otherwise>
                         <td><a href="{concat('./',@QValuePerBase)}"><img alt="Q-value per base" src="{concat('./',@QValuePerBaseThumb)}"/></a></td>
                       </xsl:otherwise>
                     </xsl:choose>
		    </tr>
		  </xsl:for-each>
		</xsl:for-each>
	      </tbody>
	    </table>
	  </div>
	  </div>

	  <div>
	  <div class="section">
	    <h2>Metrics aggregated per project</h2>
	    <table>
	      <thead>
		<tr>
		  <th>Read</th>
		  <th>Lane</th>
		  <th>Yield<br/>PF (bp)</th>
		  <th>Clusters<br/>PF</th>
		  <th>Q&#8805;30(%)</th>
		  <th>Yield<br/>Q&#8805;30 (bp)</th>
		  <th>MeanQ</th>
                  <th>Q-score per base<br />A/C/G/T</th>
		  <th>Q-score<br/>distribution</th>
		  <th>Base<br/>composition</th>
		  <th>GC<br/>distribution</th>
		  <th>Contiguous Length<br/>with Q&#8805;30 (bp)</th>
		  <th>Duplicates</th>
		  <th>Adapter<br/>sequences</th>
                  <th>Q-score per base<br/> and position</th>
		</tr>
	      </thead>
	      <tbody>
		<xsl:for-each select="ProjectMetrics/Project">
		  <tr class="SampleName">
                    <td colspan="15" class="SampleName"><a href="{concat('./', @Id, '/report.html')}"><xsl:value-of select="@Id"/></a></td>
		  </tr>
		  <xsl:for-each select="./Read">
		    <xsl:variable name="row-class">
		      <xsl:choose>
			<xsl:when test="position() mod 2 = 0">even</xsl:when>
			<xsl:otherwise>odd</xsl:otherwise>
		      </xsl:choose>
		    </xsl:variable>
		    <xsl:variable name="LaneRows">
		      <xsl:value-of select="count(descendant::Lane)"/>
		    </xsl:variable>
		    <xsl:for-each select="./Lane">
		      <tr class="{$row-class}">
			  <xsl:attribute name="style">
			    <xsl:choose>
			      <!-- Set red background if Undetermined sequences has more data than half of that expected per sample -->
			      <xsl:when test="../../@Id='Undetermined_indices' and @PctLane &gt; (50 div /SummaryReport/LaneMetrics/Lane[@Id=current()/@Id]/Read[@Id=1]/@SamplesOnLane)">
				<xsl:text>background: #ff7777; color: black;</xsl:text>
			      </xsl:when>
			    </xsl:choose>
			  </xsl:attribute>
			<xsl:if test="count(preceding-sibling::Lane) = 0">
			  <td rowspan="{$LaneRows}"><xsl:value-of select="../@Id"/></td>
			</xsl:if>
			<td><xsl:value-of select="@Id"/></td>
			<td>
			  <xsl:call-template name="format-suffix">
			    <xsl:with-param name="myval" select="@YieldPF" />
			    <xsl:with-param name="precision" select="1" />
			  </xsl:call-template>
			</td>
			<td>
			  <xsl:call-template name="format-suffix">
			    <xsl:with-param name="myval" select="@PF" />
			    <xsl:with-param name="precision" select="1" />
			  </xsl:call-template>
			</td>
			<td><xsl:value-of select="format-number(round((@YieldQ30 * 1000) div @YieldPF) div 10, '##.0')"/></td>
			<td>
			  <xsl:call-template name="format-suffix">
			    <xsl:with-param name="myval" select="@YieldQ30" />
			    <xsl:with-param name="precision" select="1" />
			  </xsl:call-template>
			</td>
			<td><xsl:value-of select="@QMean"/><span class="stddev">&#177;<xsl:value-of select="@QStdDev"/></span></td>
                        <td>
                          <xsl:value-of select="@QValuePerBaseAMean"/><span class="stddev">&#177;<xsl:value-of select="@QValuePerBaseAStdv"/></span><br/>
                          <xsl:value-of select="@QValuePerBaseCMean"/><span class="stddev">&#177;<xsl:value-of select="@QValuePerBaseCStdv"/></span><br/>
                          <xsl:value-of select="@QValuePerBaseGMean"/><span class="stddev">&#177;<xsl:value-of select="@QValuePerBaseGStdv"/></span><br/>
                          <xsl:value-of select="@QValuePerBaseTMean"/><span class="stddev">&#177;<xsl:value-of select="@QValuePerBaseTStdv"/></span>
                        </td>
			<xsl:choose>
			  <xsl:when test="@QscorePlot = &apos;NA&apos;">
			    <td>NA</td>
			  </xsl:when>
			  <xsl:otherwise>
			    <td><a href="{concat('./',@QscorePlot)}"><img alt="Qscore Plot" src="{concat('./',@QscorePlotThumb)}"/></a></td>
			  </xsl:otherwise>
			</xsl:choose>

			<xsl:choose>
			<xsl:when test="@BaseCompPlot = &apos;NA&apos;">
			  <td>NA</td>
			</xsl:when>
			<xsl:otherwise>
			  <td><a href="{concat('./',@BaseCompPlot)}"><img alt="Base Composition Plot" src="{concat('./',@BaseCompPlotThumb)}"/></a></td>
			</xsl:otherwise>
			</xsl:choose>

			<xsl:choose>
			  <xsl:when test="@GCPlot = &apos;NA&apos;">
			    <td>NA</td>
			  </xsl:when>
			  <xsl:otherwise>
			    <td><a href="{concat('./',@GCPlot)}"><img alt="GC Plot" src="{concat('./',@GCPlotThumb)}"/></a></td>
			  </xsl:otherwise>
			</xsl:choose>

			<xsl:choose>
			  <xsl:when test="@Q30Plot = &apos;NA&apos;">
			    <td>NA</td>
			  </xsl:when>
			  <xsl:otherwise>
			    <td><a href="{concat('./',@Q30Plot)}"><img alt="Q30Length Plot" src="{concat('./',@Q30PlotThumb)}"/></a></td>
			  </xsl:otherwise>
			</xsl:choose>

			<xsl:choose>
			  <xsl:when test="@DupPlot = &apos;NA&apos;">
			    <td>NA</td>
			  </xsl:when>
			  <xsl:otherwise>
			    <td><a href="{concat('./',@DupPlot)}"><img alt="Duplication Plot" src="{concat('./',@DupPlotThumb)}"/></a></td>
			  </xsl:otherwise>
			</xsl:choose>

			<xsl:choose>
			  <xsl:when test="@AdapterPlot = &apos;NA&apos;">
			    <td>NA</td>
			  </xsl:when>
			  <xsl:otherwise>
			    <td><a href="{concat('./',@AdapterPlot)}"><img alt="Adapter Plot" src="{concat('./',@AdapterPlotThumb)}"/></a></td>
			  </xsl:otherwise>
			</xsl:choose>

                        <xsl:choose>
                         <xsl:when test="@QValuePerBase = &apos;NA&apos;">
                           <td>NA</td>
                         </xsl:when>
                         <xsl:otherwise>
                           <td><a href="{concat('./',@QValuePerBase)}"><img alt="Q-value per base" src="{concat('./',@QValuePerBaseThumb)}"/></a></td>
                         </xsl:otherwise>
                       </xsl:choose>

		      </tr>
		    </xsl:for-each>
		  </xsl:for-each>
		</xsl:for-each>
	      </tbody>
	    </table>
	  </div>
	</div>

	<div>
	<div class="section">
	<h2>Run parameters</h2>
	<table class="MetaData">
	  <tr class="odd">
	    <td>Run Folder</td>
	    <td><xsl:value-of select="MetaData/@RunFolder"/></td>
	  </tr>

	  <xsl:for-each select="MetaData/Read">
	    <tr >
	      <td>Read <xsl:value-of select="@Id"/></td>
	      <td><xsl:value-of select="@Cycles"/>bp</td>
	    </tr>
	  </xsl:for-each>

	  <tr >
	    <td>Cluster Kit</td>
	    <td><xsl:value-of select="MetaData/@ClusterKitVersion"/></td>
	  </tr>

	  <tr >
	    <td>Flow Cell ID</td>
	    <td><xsl:value-of select="MetaData/@FlowCellId"/></td>
	  </tr>

	  <tr >
	    <td>Flow Cell Version</td>
	    <td><xsl:value-of select="MetaData/@FlowCellVer"/></td>
	  </tr>

	  <tr >
	    <td>Chemistry</td>
	    <td><xsl:value-of select="MetaData/@SBSversion"/></td>
	  </tr>

	  <tr >
	    <td>Instrument Type</td>
	    <td><xsl:value-of select="MetaData/@InstrumentModel"/></td>
	  </tr>

	  <tr >
	    <td>HiSeq Control Software</td>
	    <td><xsl:value-of select="MetaData/@CsVersion"/></td>
	  </tr>

	  <tr >
	    <td>RTA Version</td>
	    <td><xsl:value-of select="MetaData/@RtaVersion"/></td>
	  </tr>

	  <tr >
	    <td>Sisyphus Version</td>
	    <td><xsl:value-of select="MetaData/@SisyphusVersion"/></td>
	  </tr>

	  <tr >
	    <td>Q-Score Offset</td>
	    <td><xsl:value-of select="MetaData/@Qoffset"/></td>
      </tr>

      <tr >
        <td>bcl2fastq Version</td>
        <td><xsl:value-of select="MetaData/@bcl2fastqVersion"/></td>
      </tr>    

	</table>
	</div>

	<div class="section">
	<h2>Table key</h2>
	  <table class="key">
	    <tr>
	      <td>Raw Density</td>
	      <td>Average number of clusters per square mm</td>
	    </tr>

	    <tr>
	      <td>Pass Filter</td>
	      <td>Fraction of sequences that passed Illumina's chastity filter. Only the sequences that passed the filter are reported</td>
	    </tr>

	    <tr>
	      <td>Yield PF</td>
	      <td>Total number of bases from pass filter reads</td>
	    </tr>

	    <tr>
	      <td>Clusters PF</td>
	      <td>Number of clusters (sequences) pass filter</td>
	    </tr>

	    <tr>
	      <td>Q&#8805;30</td>
	      <td>Fraction of all pass filter bases with Q-score &#8805;30</td>
	    </tr>

	    <tr>
	      <td>Yield Q&#8805;30</td>
	      <td>Number of bases with Q-score &#8805;30</td>
	    </tr>

	    <tr>
	      <td>MeanQ</td>
	      <td>Mean Q-score over all sequences (&#177;Standard deviation)</td>
	    </tr>

	    <tr>
	      <td>Q-score distribution</td>
	      <td>A plot showing the distribution of Q-scores per cycle</td>
	    </tr>

	    <tr>
	      <td>Base composition</td>
	      <td>Plot on the relative fraction of each base per cycle</td>
	    </tr>

	    <tr>
	      <td>GC distribution</td>
	      <td>Distribution of GC-content in the sequenced fragments</td>
	    </tr>

	    <tr>
	      <td>Contiguous Length with Q&#8805;30</td>
	      <td>Plot on the length distribution of the longest contiguous stretch of bases with Q-score &lt; 30</td>
	    </tr>

	    <tr>
	      <td>Duplicates</td>
	      <td>Frequency of duplicated sequences. The numbers are estimated by following the first 100,000 unique sequences through the whole file.
	      Identity is based on the first 50 bases.</td>
	    </tr>

	    <tr>
	      <td>Adapter sequences</td>
	      <td>Cumulative fraction of sequences matching the adapter sequence, starting at cycle X. The match must be at least 6 bases, have at most 1 mismatch per 10 bases and extend to the end of the read or adapter sequence.</td>
	    </tr>

	  </table>
	</div>
	</div>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
