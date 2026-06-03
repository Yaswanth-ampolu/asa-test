---
{
  "section": "IV",
  "section_title": "Appendix D: SPI Tunneling Waveform Examples (Informative)",
  "module": "Appendices",
  "depth": 1,
  "page_start": 341,
  "page_end": 347,
  "content_type": "figure",
  "register_address": null,
  "tables": [],
  "figures": [
    {
      "id": "IV-1",
      "title": "SPI ASEP tunneling–Write/Read example"
    },
    {
      "id": "IV-2",
      "title": "SPI ASEP tunneling–Single/Multi Write/Read example 2"
    },
    {
      "id": "IV-3",
      "title": "SPI ASEP tunneling–Single/Multi Write only example 3"
    },
    {
      "id": "IV-4",
      "title": "SPI ASEP tunneling–Write/Read with longer SPI frame example 4"
    },
    {
      "id": "IV-5",
      "title": "SPI ASEP tunneling–Write/Read with longer SPI frame without “reduce latency” example 5"
    },
    {
      "id": "IV-6",
      "title": "SPI ASEP tunneling–“Motorola mode” CS operation example"
    },
    {
      "id": "IV-7",
      "title": "SPI ASEP tunneling–“TI mode” CS operation example"
    }
  ],
  "source": "ASA_Technical_Specification_ver2.0.pdf"
}
---

# IV Appendix D: SPI Tunneling Waveform Examples (Informative)

31.Then, ASD de asserts S_CS.
32.After SPI master complete to receive all of SPI return
data, SPI master de asserts CS#0 to finish the SPI
communication.
Figure IV-4: SPI ASEP tunneling–Write/Read with longer SPI frame example 4
This time chart shows the reduce latency setting off.
The processes are almost as same as Figure IV-4.
However, process #(6) is different. The first SPI data
(O_DB#1) is temporarily stored in the buffer memory
to wait at least theminimum latency time “L” to avoid
occurring the underflow at the far side. The ASE
outputs the O_DB#1 to the uplink assigned to transmit
SPI packet which is coming first is coming first after
the“L” time
As a result, the arrival time of O_DB#1 is late, but ASD
of ASA node 2 (far side) does not need to pause SCK to
wait the following available SPI data arrivals.
Figure IV-5: SPI ASEP tunneling–Write/Read with longer SPI frame without “reduce latency” example 5
Figure IV-6: SPI ASEP tunneling–“Motorola mode” CS operation example
Figure IV-7: SPI ASEP tunneling–“TI mode” CS operation example
