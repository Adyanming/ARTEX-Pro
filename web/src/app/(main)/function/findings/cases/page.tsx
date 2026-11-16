"use client";

import * as React from "react";

import Link from "next/link";

import { ChevronRightIcon } from "lucide-react";

import { FindingSeverityCounts } from "@/components/finding-case-list";
import { TablePagination } from "@/components/table-pagination";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Spinner } from "@/components/ui/spinner";
import { api } from "@/lib/api";
import type { FindingCasePage } from "@/lib/types";

// Merged cases overview: a lightweight index of the consolidated vulnerability groups
// (several findings describing the same issue folded into one report). The detail view
// lives at /function/findings/case?id=... and the full merge workbench is <FindingCaseList />.
export default function FindingCasesPage() {
  const [data, setData] = React.useState<FindingCasePage | null>(null);
  const [error, setError] = React.useState("");
  const [page, setPage] = React.useState(1);
  const [pageSize, setPageSize] = React.useState(20);
  const [loading, setLoading] = React.useState(true);
  const [refresh, setRefresh] = React.useState(0);

  // biome-ignore lint/correctness/useExhaustiveDependencies: refresh is an explicit retry request.
  React.useEffect(() => {
    let active = true;
    setLoading(true);
    api
      .findingCases({ page, pageSize })
      .then((v) => {
        if (!active) return;
        setData(v);
        setError("");
      })
      .catch((e) => {
        if (active) setError((e as Error).message);
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [page, pageSize, refresh]);

  const rows = data?.items ?? [];

  return (
    <div className="flex flex-1 flex-col gap-4 md:gap-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">漏洞归并组</h1>
          <p className="text-muted-foreground text-sm">同一漏洞的多条上报已归并为一份统一报告</p>
        </div>
        <Button variant="outline" asChild>
          <Link href="/function/findings">返回漏洞列表</Link>
        </Button>
      </div>

      {data ? (
        <p className="text-muted-foreground text-xs tabular-nums">
          {data.stats.total} 个独立漏洞 · {data.stats.reports} 条上报
        </p>
      ) : null}

      {error ? (
        <Card>
          <CardContent className="flex items-center gap-2 py-6 text-sm">
            <span className="text-destructive">加载失败：{error}</span>
            <Button variant="link" onClick={() => setRefresh((v) => v + 1)}>
              重试
            </Button>
          </CardContent>
        </Card>
      ) : null}

      {loading && !data ? (
        <div className="flex justify-center p-8">
          <Spinner />
        </div>
      ) : null}

      <div className="flex min-w-0 flex-col gap-3">
        {rows.map((row) => {
          const c = row.case;
          const title = c?.title || row.finding?.name || row.finding?.vulnclass || "未命名漏洞组";
          const counts = c ?? { critical: 0, high: 0, medium: 0, low: 0 };
          return (
            <Card key={c ? `case:${c.id}` : `finding:${row.finding?.finding_id ?? row.finding?.id ?? title}`}>
              <CardContent className="flex flex-wrap items-center gap-3 py-3">
                <div className="flex min-w-0 flex-1 flex-wrap items-center gap-2">
                  <FindingSeverityCounts counts={counts} />
                  {c ? (
                    <Link
                      href={`/function/findings/case?id=${encodeURIComponent(c.id)}`}
                      className="truncate font-medium text-sm hover:underline"
                    >
                      {title}
                    </Link>
                  ) : (
                    <span className="truncate font-medium text-sm">{title}</span>
                  )}
                  {c ? (
                    <Badge variant="secondary" className="tabular-nums">
                      {c.count} 条上报
                    </Badge>
                  ) : (
                    <Badge variant="outline">未归并</Badge>
                  )}
                  {c && !c.active ? <Badge variant="outline">已解散</Badge> : null}
                  {row.task_name || row.task_description ? (
                    <span className="truncate text-muted-foreground text-xs">
                      {row.task_name || row.task_description}
                    </span>
                  ) : null}
                  {row.last_found_at ? (
                    <span className="text-muted-foreground text-xs tabular-nums">
                      {new Date(row.last_found_at).toLocaleString("zh-CN")}
                    </span>
                  ) : null}
                </div>
                {c ? (
                  <Button variant="ghost" size="sm" asChild>
                    <Link href={`/function/findings/case?id=${encodeURIComponent(c.id)}`}>
                      查看统一报告
                      <ChevronRightIcon />
                    </Link>
                  </Button>
                ) : null}
              </CardContent>
            </Card>
          );
        })}
        {data && data.total === 0 ? (
          <p className="p-6 text-center text-muted-foreground text-sm">暂无归并组</p>
        ) : null}
      </div>

      {data && data.total > 0 ? (
        <TablePagination
          page={page}
          pageSize={pageSize}
          total={data.total}
          onPageChange={setPage}
          onPageSizeChange={(s) => {
            setPageSize(s);
            setPage(1);
          }}
          pageSizeOptions={[10, 20, 50]}
        />
      ) : null}
    </div>
  );
}
